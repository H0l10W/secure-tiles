"""Run the Secure Tiles username directory and opaque-message relay.

The server stores public contact cards and ciphertext. It never receives private
keys or plaintext. Put it behind an HTTPS reverse proxy for non-local use.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import sqlite3
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from secure_tiles.crypto import CryptoError, validate_card

MAX_REQUEST_BYTES = 2 * 1024 * 1024
MAX_ATTACHMENT_BYTES = 50 * 1024 * 1024
MAX_ATTACHMENT_CHUNKS = 50


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
            CREATE TABLE IF NOT EXISTS attachments (
              id TEXT PRIMARY KEY, token_hash TEXT NOT NULL, recipient TEXT NOT NULL,
              total_size INTEGER NOT NULL, chunks INTEGER NOT NULL, created INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS attachment_chunks (
              attachment_id TEXT NOT NULL, chunk_index INTEGER NOT NULL, data BLOB NOT NULL,
              PRIMARY KEY (attachment_id, chunk_index)
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

    @staticmethod
    def _token_hash(token: str) -> str:
        return hashlib.sha256(token.encode("ascii")).hexdigest()

    def begin_attachment(self, attachment_id: str, token: str, recipient: str, total_size: int, chunks: int) -> None:
        if not (1 <= total_size <= MAX_ATTACHMENT_BYTES and 1 <= chunks <= MAX_ATTACHMENT_CHUNKS):
            raise ValueError("Invalid attachment size")
        with self.lock:
            existing = self.connection.execute("SELECT * FROM attachments WHERE id = ?", (attachment_id,)).fetchone()
            values = (self._token_hash(token), recipient, total_size, chunks)
            if existing:
                if (existing["token_hash"], existing["recipient"], existing["total_size"], existing["chunks"]) != values:
                    raise ValueError("Attachment upload does not match its existing transfer")
                return
            self.connection.execute("INSERT INTO attachments VALUES (?, ?, ?, ?, ?, ?)",
                                    (attachment_id, *values, int(time.time())))
            self.connection.commit()

    def attachment_status(self, attachment_id: str, token: str) -> list[int]:
        with self.lock:
            row = self.connection.execute("SELECT token_hash FROM attachments WHERE id = ?", (attachment_id,)).fetchone()
            if not row or row["token_hash"] != self._token_hash(token): raise ValueError("Invalid attachment transfer")
            rows = self.connection.execute("SELECT chunk_index FROM attachment_chunks WHERE attachment_id = ? ORDER BY chunk_index", (attachment_id,)).fetchall()
        return [int(item["chunk_index"]) for item in rows]

    def put_attachment_chunk(self, attachment_id: str, token: str, index: int, encoded: str) -> None:
        try: data = base64.b64decode(encoded.encode("ascii"), altchars=b"-_", validate=True)
        except (ValueError, UnicodeEncodeError) as exc: raise ValueError("Invalid attachment chunk") from exc
        if len(data) > 1024 * 1024 + 64: raise ValueError("Attachment chunk is too large")
        with self.lock:
            row = self.connection.execute("SELECT token_hash, chunks FROM attachments WHERE id = ?", (attachment_id,)).fetchone()
            if not row or row["token_hash"] != self._token_hash(token) or not 0 <= index < row["chunks"]:
                raise ValueError("Invalid attachment transfer")
            self.connection.execute("INSERT OR IGNORE INTO attachment_chunks VALUES (?, ?, ?)", (attachment_id, index, data))
            self.connection.commit()

    def attachment_chunk(self, attachment_id: str, token: str, index: int) -> bytes:
        with self.lock:
            meta = self.connection.execute("SELECT token_hash, chunks FROM attachments WHERE id = ?", (attachment_id,)).fetchone()
            if not meta or meta["token_hash"] != self._token_hash(token) or not 0 <= index < meta["chunks"]:
                raise ValueError("Invalid attachment transfer")
            row = self.connection.execute("SELECT data FROM attachment_chunks WHERE attachment_id = ? AND chunk_index = ?", (attachment_id, index)).fetchone()
        if not row: raise ValueError("Attachment chunk is unavailable")
        return bytes(row["data"])

    def complete_attachment(self, attachment_id: str, token: str) -> None:
        with self.lock:
            row = self.connection.execute("SELECT token_hash FROM attachments WHERE id = ?", (attachment_id,)).fetchone()
            if not row or row["token_hash"] != self._token_hash(token): raise ValueError("Invalid attachment transfer")
            self.connection.execute("DELETE FROM attachment_chunks WHERE attachment_id = ?", (attachment_id,))
            self.connection.execute("DELETE FROM attachments WHERE id = ?", (attachment_id,))
            self.connection.commit()


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
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_REQUEST_BYTES:
            raise ValueError("Request is too large")
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
            parts = self.path.split("/")
            if len(parts) == 5 and parts[2] == "attachments":
                attachment_id, action = parts[3], parts[4]
                if len(attachment_id) > 64: raise ValueError("Invalid attachment identifier")
                body = self.body(); token = str(body.get("token", ""))
                if action == "begin":
                    self.db.begin_attachment(attachment_id, token, str(body["recipient"]), int(body["total_size"]), int(body["chunks"]))
                    return self.reply(200, {"ok": True})
                if action == "status": return self.reply(200, {"received": self.db.attachment_status(attachment_id, token)})
                if action == "chunk":
                    self.db.put_attachment_chunk(attachment_id, token, int(body["index"]), str(body["data"]))
                    return self.reply(200, {"ok": True})
                if action == "download":
                    data = self.db.attachment_chunk(attachment_id, token, int(body["index"]))
                    return self.reply(200, {"data": base64.urlsafe_b64encode(data).decode("ascii")})
                if action == "complete":
                    self.db.complete_attachment(attachment_id, token)
                    return self.reply(200, {"ok": True})
            if self.path != "/v1/messages": return self.reply(404, {"error": "Not found"})
            packet = self.body()
            required = ("protocol", "type", "id", "to", "from", "ciphertext")
            if any(key not in packet for key in required) or len(json.dumps(packet).encode("utf-8")) > MAX_REQUEST_BYTES:
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
