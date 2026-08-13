"""Run the Secure Tiles username directory and opaque-message relay.

The server stores public contact cards and ciphertext. It never receives private
keys or plaintext. Put it behind an HTTPS reverse proxy for non-local use.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from secure_tiles.crypto import CryptoError, validate_card


class Database:
    def __init__(self, path: Path):
        self.connection = sqlite3.connect(path, check_same_thread=False)
        self.connection.row_factory = sqlite3.Row
        self.lock = threading.Lock()
        self.connection.executescript("""
            CREATE TABLE IF NOT EXISTS users (
              name TEXT PRIMARY KEY COLLATE NOCASE, encryption_key TEXT UNIQUE NOT NULL,
              signing_key TEXT UNIQUE NOT NULL, card TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS queue (
              id TEXT PRIMARY KEY, recipient TEXT NOT NULL, packet TEXT NOT NULL,
              created INTEGER NOT NULL
            );
        """)

    def register(self, card: dict[str, str]) -> None:
        username = card["name"].strip().casefold()
        with self.lock:
            try:
                self.connection.execute("BEGIN IMMEDIATE")
                existing = self.connection.execute("SELECT signing_key FROM users WHERE name = ?", (username,)).fetchone()
                if existing and existing["signing_key"] != card["signing_key"]:
                    raise ValueError("That username is already taken. Choose another one.")
                if existing:
                    self.connection.execute("UPDATE users SET card = ? WHERE name = ?", (json.dumps(card), username))
                else:
                    self.connection.execute("INSERT INTO users VALUES (?, ?, ?, ?)",
                                            (username, card["encryption_key"], card["signing_key"], json.dumps(card)))
                self.connection.commit()
            except Exception:
                self.connection.rollback()
                raise

    def lookup(self, name: str) -> dict[str, str] | None:
        with self.lock:
            row = self.connection.execute("SELECT card FROM users WHERE name = ?", (name.strip().casefold(),)).fetchone()
        return json.loads(row["card"]) if row else None

    def enqueue(self, packet: dict[str, Any]) -> None:
        with self.lock:
            recipient = self.connection.execute("SELECT 1 FROM users WHERE encryption_key = ?", (packet["to"],)).fetchone()
            if not recipient: raise ValueError("Recipient is not registered")
            self.connection.execute(
                "INSERT OR IGNORE INTO queue VALUES (?, ?, ?, ?)",
                (packet["id"], packet["to"], json.dumps(packet), int(time.time())),
            )
            self.connection.commit()

    def drain(self, recipient: str) -> list[dict[str, Any]]:
        with self.lock:
            rows = self.connection.execute("SELECT id, packet FROM queue WHERE recipient = ? ORDER BY created", (recipient,)).fetchall()
            if rows:
                self.connection.executemany("DELETE FROM queue WHERE id = ?", [(row["id"],) for row in rows])
                self.connection.commit()
        return [json.loads(row["packet"]) for row in rows]


class Handler(BaseHTTPRequestHandler):
    db: Database
    server_version = "SecureTilesRelay/0.2"

    def log_message(self, fmt, *args):
        print(f"[{self.log_date_time_string()}] {fmt % args}")

    def reply(self, status: int, value: dict[str, Any]):
        data = json.dumps(value).encode("utf-8")
        self.send_response(status); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)

    def body(self) -> dict[str, Any]:
        length = min(int(self.headers.get("Content-Length", "0")), 100_000)
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def do_PUT(self):
        try:
            if self.path != "/v1/users": return self.reply(404, {"error": "Not found"})
            card = validate_card(self.body())
            if not card["name"] or len(card["name"]) > 32 or not card["name"].replace("_", "").isalnum():
                raise ValueError("Username must use 1-32 letters, numbers, or underscores")
            self.db.register(card); self.reply(200, {"ok": True})
        except (ValueError, CryptoError, json.JSONDecodeError) as exc: self.reply(400, {"error": str(exc)})

    def do_POST(self):
        try:
            if self.path != "/v1/messages": return self.reply(404, {"error": "Not found"})
            packet = self.body()
            required = ("protocol", "type", "id", "to", "from", "ciphertext")
            if any(key not in packet for key in required) or len(json.dumps(packet)) > 100_000:
                raise ValueError("Invalid packet")
            self.db.enqueue(packet); self.reply(200, {"ok": True})
        except (KeyError, ValueError, json.JSONDecodeError) as exc: self.reply(400, {"error": str(exc)})

    def do_GET(self):
        parts = self.path.split("/", 3)
        if len(parts) != 4: return self.reply(404, {"error": "Not found"})
        value = urllib.parse.unquote(parts[3])
        if parts[2] == "users":
            card = self.db.lookup(value)
            return self.reply(200, card) if card else self.reply(404, {"error": "Username not found"})
        if parts[2] == "messages": return self.reply(200, {"messages": self.db.drain(value)})
        self.reply(404, {"error": "Not found"})


def main():
    parser = argparse.ArgumentParser(description="Secure Tiles encrypted-message relay")
    parser.add_argument("--host", default="127.0.0.1"); parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--database", type=Path, default=Path("relay.db")); args = parser.parse_args()
    Handler.db = Database(args.database)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Secure Tiles relay listening on http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nSecure Tiles relay stopped.")
    finally:
        server.server_close()
        Handler.db.connection.close()


if __name__ == "__main__": main()
