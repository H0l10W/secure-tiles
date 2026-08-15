"""Run the Secure Tiles username directory and opaque-message relay.

The server stores public contact cards and ciphertext. It never receives private
keys or plaintext. Put it behind an HTTPS reverse proxy for non-local use.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sqlite3
import threading
import time
import urllib.parse
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from secure_tiles.crypto import CryptoError, validate_card
from secure_tiles.servers import DEFAULT_ROLES, normalize_channel_name, normalize_server_name, role_permissions, validate_server_action

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
            CREATE TABLE IF NOT EXISTS typing (
              sender TEXT NOT NULL, recipient TEXT NOT NULL, packet TEXT NOT NULL,
              updated INTEGER NOT NULL, PRIMARY KEY (sender, recipient)
            );
            CREATE TABLE IF NOT EXISTS presence (
              sender TEXT NOT NULL, recipient TEXT NOT NULL, packet TEXT NOT NULL,
              updated INTEGER NOT NULL, PRIMARY KEY (sender, recipient)
            );
            CREATE TABLE IF NOT EXISTS attachments (
              id TEXT PRIMARY KEY, token_hash TEXT NOT NULL, recipient TEXT NOT NULL,
              total_size INTEGER NOT NULL, chunks INTEGER NOT NULL, created INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS attachment_chunks (
              attachment_id TEXT NOT NULL, chunk_index INTEGER NOT NULL, data BLOB NOT NULL,
              PRIMARY KEY (attachment_id, chunk_index)
            );
            CREATE TABLE IF NOT EXISTS servers (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, owner_key TEXT NOT NULL,
              accent TEXT NOT NULL, icon TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS server_members (
              server_id TEXT NOT NULL, signing_key TEXT NOT NULL, card TEXT NOT NULL,
              roles TEXT NOT NULL, joined INTEGER NOT NULL, PRIMARY KEY (server_id, signing_key)
            );
            CREATE TABLE IF NOT EXISTS server_roles (
              server_id TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL, color TEXT NOT NULL,
              permissions TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (server_id, id)
            );
            CREATE TABLE IF NOT EXISTS server_channels (
              server_id TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL, type TEXT NOT NULL,
              position INTEGER NOT NULL, topic TEXT NOT NULL DEFAULT '', PRIMARY KEY (server_id, id)
            );
            CREATE TABLE IF NOT EXISTS server_invites (
              code TEXT PRIMARY KEY, server_id TEXT NOT NULL, role_id TEXT NOT NULL,
              creator TEXT NOT NULL, expires INTEGER NOT NULL, uses_left INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS server_action_nonces (
              nonce TEXT PRIMARY KEY, created INTEGER NOT NULL
            );
        """)

    def _server_permissions(self, server_id: str, actor: str) -> set[str]:
        server = self.connection.execute("SELECT owner_key FROM servers WHERE id = ?", (server_id,)).fetchone()
        if not server: raise ValueError("Server not found")
        if server["owner_key"] == actor: return {permission for role in DEFAULT_ROLES for permission in role["permissions"]}
        member = self.connection.execute("SELECT roles FROM server_members WHERE server_id = ? AND signing_key = ?", (server_id, actor)).fetchone()
        if not member: raise ValueError("You are not a member of this server")
        role_ids = json.loads(member["roles"]); permissions: set[str] = set()
        if role_ids:
            marks = ",".join("?" for _ in role_ids)
            rows = self.connection.execute(f"SELECT permissions FROM server_roles WHERE server_id = ? AND id IN ({marks})", (server_id, *role_ids)).fetchall()
            for row in rows: permissions.update(json.loads(row["permissions"]))
        return permissions

    def server_action(self, signed: dict[str, Any]) -> dict[str, Any]:
        action = validate_server_action(signed); server_id, actor, payload = action["server_id"], action["actor"], action["payload"]
        with self.lock:
            try:
                self.connection.execute("BEGIN IMMEDIATE")
                if self.connection.execute("SELECT 1 FROM server_action_nonces WHERE nonce = ?", (action["nonce"],)).fetchone():
                    raise ValueError("Server action was already used")
                if action["action"] == "server.create":
                    card = validate_card(payload["owner_card"])
                    if card["signing_key"] != actor: raise ValueError("Server owner identity does not match")
                    self.connection.execute("INSERT INTO servers VALUES (?, ?, ?, ?, ?, ?)",
                                            (server_id, normalize_server_name(payload["name"]), actor, str(payload.get("accent", "#5865f2"))[:16], "", int(time.time())))
                    for position, role in enumerate(DEFAULT_ROLES):
                        self.connection.execute("INSERT INTO server_roles VALUES (?, ?, ?, ?, ?, ?)",
                                                (server_id, role["id"], role["name"], role["color"], json.dumps(role["permissions"]), position))
                    self.connection.execute("INSERT INTO server_members VALUES (?, ?, ?, ?, ?)",
                                            (server_id, actor, json.dumps(card), json.dumps(["admin"]), int(time.time())))
                    self.connection.execute("INSERT INTO server_channels VALUES (?, ?, ?, 'text', 0, '')", (server_id, uuid.uuid4().hex, "general"))
                else:
                    required = {"server.update": "manage_server", "server.delete": "manage_server", "channel.create": "manage_channels", "channel.update": "manage_channels",
                                "channel.delete": "manage_channels", "role.create": "manage_roles", "role.update": "manage_roles",
                                "role.delete": "manage_roles", "member.roles": "manage_roles", "invite.create": "create_invites",
                                "invite.revoke": "create_invites", "message.send": "send_messages"}.get(action["action"])
                    if action["action"] == "invite.redeem":
                        invite = self.connection.execute("SELECT * FROM server_invites WHERE code = ? AND server_id = ?", (str(payload["code"]), server_id)).fetchone()
                        if not invite or (invite["expires"] and invite["expires"] < int(time.time())) or invite["uses_left"] == 0: raise ValueError("Invite is invalid or expired")
                        card = validate_card(payload["member_card"])
                        if card["signing_key"] != actor: raise ValueError("Invite identity does not match")
                        self.connection.execute("INSERT OR IGNORE INTO server_members VALUES (?, ?, ?, ?, ?)", (server_id, actor, json.dumps(card), json.dumps([invite["role_id"]]), int(time.time())))
                        if invite["uses_left"] > 0: self.connection.execute("UPDATE server_invites SET uses_left = uses_left - 1 WHERE code = ?", (invite["code"],))
                    else:
                        if required not in self._server_permissions(server_id, actor): raise ValueError("You do not have permission for that server action")
                        if action["action"] == "server.delete":
                            owner = self.connection.execute("SELECT owner_key FROM servers WHERE id = ?", (server_id,)).fetchone()
                            if not owner or owner["owner_key"] != actor: raise ValueError("Only the server owner can delete this server")
                            for table in ("server_invites", "server_channels", "server_members", "server_roles"):
                                self.connection.execute(f"DELETE FROM {table} WHERE server_id = ?", (server_id,))
                            self.connection.execute("DELETE FROM servers WHERE id = ?", (server_id,))
                        elif action["action"] == "message.send":
                            self._enqueue_server_message(server_id, actor, payload)
                        else:
                            self._apply_server_mutation(server_id, action["action"], payload, actor)
                self.connection.execute("INSERT INTO server_action_nonces VALUES (?, ?)", (action["nonce"], int(time.time())))
                self.connection.commit()
                if action["action"] == "server.delete": return {"deleted": True, "id": server_id}
                return self.server_snapshot(server_id)
            except Exception:
                self.connection.rollback(); raise

    def _apply_server_mutation(self, server_id: str, action: str, payload: dict[str, Any], actor: str) -> None:
        if action == "server.update":
            icon = str(payload.get("icon", ""))
            if icon and (not icon.startswith("data:image/") or len(icon) > 100_000): raise ValueError("Server icon is invalid")
            self.connection.execute("UPDATE servers SET name = ?, accent = ?, icon = ? WHERE id = ?", (normalize_server_name(payload["name"]), str(payload.get("accent", "#5865f2"))[:16], icon, server_id))
        elif action == "channel.create":
            channel_type = str(payload.get("type", "text"));
            if channel_type not in {"text", "voice"}: raise ValueError("Unsupported channel type")
            position = self.connection.execute("SELECT COUNT(*) AS count FROM server_channels WHERE server_id = ?", (server_id,)).fetchone()["count"]
            self.connection.execute("INSERT INTO server_channels VALUES (?, ?, ?, ?, ?, ?)", (server_id, uuid.uuid4().hex, normalize_channel_name(payload["name"]), channel_type, position, str(payload.get("topic", ""))[:120]))
        elif action == "channel.update":
            channel_id = str(payload["channel_id"])
            if not self.connection.execute("SELECT 1 FROM server_channels WHERE server_id = ? AND id = ?", (server_id, channel_id)).fetchone(): raise ValueError("Channel not found")
            self.connection.execute("UPDATE server_channels SET name = ?, topic = ? WHERE server_id = ? AND id = ?", (normalize_channel_name(payload["name"]), str(payload.get("topic", ""))[:120], server_id, channel_id))
        elif action == "channel.delete":
            channel_id = str(payload["channel_id"])
            count = self.connection.execute("SELECT COUNT(*) AS count FROM server_channels WHERE server_id = ? AND type = 'text'", (server_id,)).fetchone()["count"]
            channel = self.connection.execute("SELECT type FROM server_channels WHERE server_id = ? AND id = ?", (server_id, channel_id)).fetchone()
            if not channel: raise ValueError("Channel not found")
            if channel["type"] == "text" and count <= 1: raise ValueError("A server needs at least one text channel")
            self.connection.execute("DELETE FROM server_channels WHERE server_id = ? AND id = ?", (server_id, channel_id))
        elif action == "role.create":
            role_id = uuid.uuid4().hex; position = self.connection.execute("SELECT COUNT(*) AS count FROM server_roles WHERE server_id = ?", (server_id,)).fetchone()["count"]
            self.connection.execute("INSERT INTO server_roles VALUES (?, ?, ?, ?, ?, ?)", (server_id, role_id, str(payload["name"])[:32], str(payload.get("color", "#94a3b8"))[:16], json.dumps(role_permissions(payload.get("permissions", []))), position))
        elif action == "role.update":
            role_id = str(payload["role_id"])
            if not self.connection.execute("SELECT 1 FROM server_roles WHERE server_id = ? AND id = ?", (server_id, role_id)).fetchone(): raise ValueError("Role not found")
            self.connection.execute("UPDATE server_roles SET name = ?, color = ?, permissions = ? WHERE server_id = ? AND id = ?", (str(payload["name"])[:32], str(payload.get("color", "#94a3b8"))[:16], json.dumps(role_permissions(payload.get("permissions", []))), server_id, role_id))
        elif action == "role.delete":
            role_id = str(payload["role_id"])
            if role_id in {"admin", "member"}: raise ValueError("Built-in roles cannot be deleted")
            self.connection.execute("DELETE FROM server_roles WHERE server_id = ? AND id = ?", (server_id, role_id))
            members = self.connection.execute("SELECT signing_key, roles FROM server_members WHERE server_id = ?", (server_id,)).fetchall()
            for member in members:
                roles = [value for value in json.loads(member["roles"]) if value != role_id] or ["member"]
                self.connection.execute("UPDATE server_members SET roles = ? WHERE server_id = ? AND signing_key = ?", (json.dumps(roles), server_id, member["signing_key"]))
        elif action == "member.roles":
            if payload["member"] == self.connection.execute("SELECT owner_key FROM servers WHERE id = ?", (server_id,)).fetchone()["owner_key"]: raise ValueError("The server owner's roles cannot be changed")
            roles = list(dict.fromkeys(payload["roles"]))
            if not roles or any(not self.connection.execute("SELECT 1 FROM server_roles WHERE server_id = ? AND id = ?", (server_id, role)).fetchone() for role in roles): raise ValueError("Member roles are invalid")
            self.connection.execute("UPDATE server_members SET roles = ? WHERE server_id = ? AND signing_key = ?", (json.dumps(roles), server_id, payload["member"]))
        elif action == "invite.create":
            code = str(payload["code"])
            if not re.fullmatch(r"[A-Za-z0-9_-]{4,32}", code): raise ValueError("Invite codes need 4-32 letters, numbers, dashes, or underscores")
            if self.connection.execute("SELECT 1 FROM server_invites WHERE code = ?", (code,)).fetchone(): raise ValueError("That invite code is already in use")
            requested_expiry = int(payload.get("expires", int(time.time()) + 86400))
            expires = 0 if requested_expiry == 0 else min(requested_expiry, int(time.time()) + 30 * 86400)
            role_id = str(payload.get("role_id", "member"))
            if not self.connection.execute("SELECT 1 FROM server_roles WHERE server_id = ? AND id = ?", (server_id, role_id)).fetchone(): raise ValueError("Invite role is invalid")
            self.connection.execute("INSERT INTO server_invites VALUES (?, ?, ?, ?, ?, ?)", (code, server_id, role_id, actor, expires, max(-1, min(100, int(payload.get("uses", -1))))))
        elif action == "invite.revoke": self.connection.execute("DELETE FROM server_invites WHERE code = ? AND server_id = ?", (payload["code"], server_id))
        else: raise ValueError("Server action is not implemented")

    def _enqueue_server_message(self, server_id: str, actor: str, payload: dict[str, Any]) -> None:
        channel = self.connection.execute("SELECT type FROM server_channels WHERE server_id = ? AND id = ?", (server_id, str(payload.get("channel_id", "")))).fetchone()
        if not channel or channel["type"] != "text": raise ValueError("Text channel not found")
        actor_row = self.connection.execute("SELECT card FROM server_members WHERE server_id = ? AND signing_key = ?", (server_id, actor)).fetchone()
        packets = payload.get("packets")
        if not isinstance(packets, list) or len(packets) > 500: raise ValueError("Invalid server message batch")
        expected = {row["encryption_key"] for row in self.connection.execute(
            "SELECT json_extract(card, '$.encryption_key') AS encryption_key FROM server_members WHERE server_id = ? AND signing_key != ?", (server_id, actor)).fetchall()}
        actual = {str(packet.get("to", "")) for packet in packets if isinstance(packet, dict)}
        if actual != expected or len(actual) != len(packets): raise ValueError("Server message recipients do not match server members")
        sender_key = json.loads(actor_row["card"])["encryption_key"]
        for packet in packets:
            required = ("protocol", "type", "id", "to", "from", "ciphertext")
            if any(key not in packet for key in required) or packet["from"] != sender_key: raise ValueError("Invalid server message packet")
            self.connection.execute("INSERT OR IGNORE INTO queue VALUES (?, ?, ?, ?)", (packet["id"], packet["to"], json.dumps(packet), int(time.time())))

    def server_snapshot(self, server_id: str) -> dict[str, Any]:
        server = self.connection.execute("SELECT * FROM servers WHERE id = ?", (server_id,)).fetchone()
        if not server: raise ValueError("Server not found")
        def rows(table: str): return [dict(row) for row in self.connection.execute(f"SELECT * FROM {table} WHERE server_id = ? ORDER BY position", (server_id,)).fetchall()]
        roles = rows("server_roles"); channels = rows("server_channels")
        for role in roles: role["permissions"] = json.loads(role["permissions"])
        members = [dict(row) for row in self.connection.execute("SELECT signing_key, card, roles, joined FROM server_members WHERE server_id = ? ORDER BY joined", (server_id,)).fetchall()]
        for member in members: member["card"], member["roles"] = json.loads(member["card"]), json.loads(member["roles"])
        return {"id": server["id"], "name": server["name"], "owner_key": server["owner_key"], "accent": server["accent"], "icon": server["icon"], "roles": roles, "channels": channels, "members": members}

    def servers_for(self, signing_key: str) -> list[dict[str, Any]]:
        rows = self.connection.execute("SELECT server_id FROM server_members WHERE signing_key = ? ORDER BY joined", (signing_key,)).fetchall()
        return [self.server_snapshot(row["server_id"]) for row in rows]

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

    def set_typing(self, packet: dict[str, Any]) -> None:
        with self.lock:
            recipient = self.connection.execute("SELECT 1 FROM users WHERE encryption_key = ?", (packet["to"],)).fetchone()
            if not recipient: raise ValueError("Recipient is not registered")
            self.connection.execute(
                "INSERT INTO typing VALUES (?, ?, ?, ?) ON CONFLICT(sender, recipient) DO UPDATE SET packet = excluded.packet, updated = excluded.updated",
                (packet["from"], packet["to"], json.dumps(packet), int(time.time())),
            )
            self.connection.commit()

    def typing(self, recipient: str) -> list[dict[str, Any]]:
        with self.lock:
            rows = self.connection.execute("SELECT packet FROM typing WHERE recipient = ? AND updated >= ?",
                                           (recipient, int(time.time()) - 5)).fetchall()
        return [json.loads(row["packet"]) for row in rows]

    def set_presence(self, packet: dict[str, Any]) -> None:
        with self.lock:
            recipient = self.connection.execute("SELECT 1 FROM users WHERE encryption_key = ?", (packet["to"],)).fetchone()
            if not recipient: raise ValueError("Recipient is not registered")
            self.connection.execute(
                "INSERT INTO presence VALUES (?, ?, ?, ?) ON CONFLICT(sender, recipient) DO UPDATE SET packet = excluded.packet, updated = excluded.updated",
                (packet["from"], packet["to"], json.dumps(packet), int(time.time())),
            )
            self.connection.commit()

    def presence(self, recipient: str) -> list[dict[str, Any]]:
        with self.lock:
            rows = self.connection.execute("SELECT packet FROM presence WHERE recipient = ? AND updated >= ?",
                                           (recipient, int(time.time()) - 45)).fetchall()
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
            if self.path in {"/v1/servers/action", "/v1/servers/messages"}:
                return self.reply(200, self.db.server_action(self.body()))
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
            if self.path not in {"/v1/messages", "/v1/typing", "/v1/presence"}: return self.reply(404, {"error": "Not found"})
            packet = self.body()
            required = ("protocol", "type", "id", "to", "from", "ciphertext")
            if any(key not in packet for key in required) or len(json.dumps(packet).encode("utf-8")) > MAX_REQUEST_BYTES:
                raise ValueError("Invalid packet")
            if self.path == "/v1/typing": self.db.set_typing(packet)
            elif self.path == "/v1/presence": self.db.set_presence(packet)
            else: self.db.enqueue(packet)
            self.reply(200, {"ok": True})
        except (KeyError, ValueError, json.JSONDecodeError) as exc: self.reply(400, {"error": str(exc)})

    def do_GET(self):
        parts = self.path.split("/", 3)
        if len(parts) != 4: return self.reply(404, {"error": "Not found"})
        value = urllib.parse.unquote(parts[3])
        if parts[2] == "servers":
            if value.startswith("member/"): return self.reply(200, {"servers": self.db.servers_for(value.removeprefix("member/"))})
            try: return self.reply(200, self.db.server_snapshot(value))
            except ValueError as exc: return self.reply(404, {"error": str(exc)})
        if parts[2] == "users":
            card = self.db.lookup(value)
            return self.reply(200, card) if card else self.reply(404, {"error": "Username not found"})
        if parts[2] == "messages": return self.reply(200, {"messages": self.db.drain(value), "typing": self.db.typing(value), "presence": self.db.presence(value)})
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
