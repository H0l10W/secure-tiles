from __future__ import annotations

import json
import base64
import os
import shutil
import sqlite3
from pathlib import Path
from typing import Any


class Store:
    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.vault_path = root / "identity.vault"
        self.attachments_path = root / "attachments"
        self.attachments_path.mkdir(exist_ok=True)
        self.db = sqlite3.connect(root / "messages.db")
        self.db.row_factory = sqlite3.Row
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS contacts (
                signing_key TEXT PRIMARY KEY, name TEXT NOT NULL,
                encryption_key TEXT NOT NULL UNIQUE, card TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY, contact_key TEXT NOT NULL, direction TEXT NOT NULL,
                sent_at INTEGER NOT NULL, plaintext TEXT NOT NULL
            );
        """)
        columns = {row["name"] for row in self.db.execute("PRAGMA table_info(messages)")}
        if "attachments" not in columns:
            self.db.execute("ALTER TABLE messages ADD COLUMN attachments TEXT NOT NULL DEFAULT '[]'")
            self.db.commit()

    def save_vault(self, vault: dict[str, Any]) -> None:
        temp = self.vault_path.with_suffix(".tmp")
        temp.write_text(json.dumps(vault), encoding="utf-8")
        os.replace(temp, self.vault_path)
        try:
            os.chmod(self.vault_path, 0o600)
        except OSError:
            pass

    def load_vault(self) -> dict[str, Any] | None:
        return json.loads(self.vault_path.read_text("utf-8")) if self.vault_path.exists() else None

    @property
    def preferences_path(self) -> Path:
        return self.root / "preferences.json"

    def preferences(self) -> dict[str, Any]:
        try:
            return json.loads(self.preferences_path.read_text("utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}

    def save_preferences(self, values: dict[str, Any]) -> None:
        temp = self.preferences_path.with_suffix(".tmp")
        temp.write_text(json.dumps(values), encoding="utf-8")
        os.replace(temp, self.preferences_path)

    def save_avatar(self, source: Path) -> Path:
        suffix = source.suffix.lower() if source.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"} else ".png"
        destination = self.root / f"avatar{suffix}"
        shutil.copy2(source, destination)
        values = self.preferences(); values["avatar"] = str(destination); self.save_preferences(values)
        return destination

    def add_contact(self, card: dict[str, str]) -> None:
        self.db.execute(
            "INSERT OR REPLACE INTO contacts VALUES (?, ?, ?, ?)",
            (card["signing_key"], card["name"], card["encryption_key"], json.dumps(card)),
        )
        self.db.commit()

    def contacts(self) -> list[dict[str, str]]:
        rows = self.db.execute("SELECT card FROM contacts ORDER BY name COLLATE NOCASE").fetchall()
        return [json.loads(row["card"]) for row in rows]

    def contact_by_encryption_key(self, key: str) -> dict[str, str] | None:
        row = self.db.execute("SELECT card FROM contacts WHERE encryption_key = ?", (key,)).fetchone()
        return json.loads(row["card"]) if row else None

    def contact_by_name(self, name: str) -> dict[str, str] | None:
        row = self.db.execute("SELECT card FROM contacts WHERE name = ? COLLATE NOCASE", (name,)).fetchone()
        return json.loads(row["card"]) if row else None

    def add_message(self, message_id: str, contact_key: str, direction: str, sent_at: int,
                    plaintext: str, attachments: list[dict[str, Any]] | None = None) -> None:
        stored_attachments = []
        for index, attachment in enumerate(attachments or []):
            if attachment.get("transfer_id") and not attachment.get("data") and not attachment.get("path"):
                stored_attachments.append(dict(attachment)); continue
            name = str(attachment.get("name", "file")).replace("\\", "/").rsplit("/", 1)[-1]
            safe_name = "".join(char if char.isalnum() or char in "._- " else "_" for char in name)[:180] or "file"
            destination = self.attachments_path / f"{message_id}-{index}-{safe_name}"
            data = attachment.get("data")
            if data:
                destination.write_bytes(base64.urlsafe_b64decode(str(data).encode("ascii")))
            elif attachment.get("path"):
                shutil.copy2(str(attachment["path"]), destination)
            else:
                continue
            stored_attachments.append({"name": name, "mime": str(attachment.get("mime", "application/octet-stream")),
                                       "size": destination.stat().st_size, "path": str(destination)})
        self.db.execute(
            "INSERT OR IGNORE INTO messages (id, contact_key, direction, sent_at, plaintext, attachments) VALUES (?, ?, ?, ?, ?, ?)",
            (message_id, contact_key, direction, sent_at, plaintext, json.dumps(stored_attachments)),
        )
        self.db.commit()

    def replace_attachments(self, message_id: str, attachments: list[dict[str, Any]]) -> None:
        if not self.message(message_id): return
        stored = []
        for index, attachment in enumerate(attachments):
            name = str(attachment.get("name", "file")).replace("\\", "/").rsplit("/", 1)[-1]
            safe_name = "".join(char if char.isalnum() or char in "._- " else "_" for char in name)[:180] or "file"
            source = Path(str(attachment.get("path", "")))
            if not source.is_file():
                stored.append(dict(attachment)); continue
            destination = self.attachments_path / f"{message_id}-{index}-{safe_name}"
            if source.resolve() != destination.resolve(): shutil.copy2(source, destination)
            stored.append({"name": name, "mime": str(attachment.get("mime", "application/octet-stream")),
                           "size": destination.stat().st_size, "path": str(destination)})
        self.db.execute("UPDATE messages SET attachments = ? WHERE id = ?", (json.dumps(stored), message_id))
        self.db.commit()

    def message(self, message_id: str) -> sqlite3.Row | None:
        return self.db.execute("SELECT * FROM messages WHERE id = ?", (message_id,)).fetchone()

    def messages(self, contact_key: str) -> list[sqlite3.Row]:
        return self.db.execute(
            "SELECT * FROM messages WHERE contact_key = ? ORDER BY sent_at, rowid", (contact_key,)
        ).fetchall()
