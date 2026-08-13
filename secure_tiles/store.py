from __future__ import annotations

import json
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

    def add_message(self, message_id: str, contact_key: str, direction: str, sent_at: int, plaintext: str) -> None:
        self.db.execute(
            "INSERT OR IGNORE INTO messages VALUES (?, ?, ?, ?, ?)",
            (message_id, contact_key, direction, sent_at, plaintext),
        )
        self.db.commit()

    def messages(self, contact_key: str) -> list[sqlite3.Row]:
        return self.db.execute(
            "SELECT * FROM messages WHERE contact_key = ? ORDER BY sent_at, rowid", (contact_key,)
        ).fetchall()
