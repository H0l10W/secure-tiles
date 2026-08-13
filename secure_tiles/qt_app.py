from __future__ import annotations

import html
import hashlib
import json
import os
import re
import socket
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import zipfile
from datetime import datetime
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlparse

from PySide6.QtCore import QObject, Property, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QColor, QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication, QColorDialog, QFileDialog

from .crypto import (
    CryptoError, Identity, decrypt_message, encrypt_message, fingerprint,
    lock_identity, public_card, unlock_identity, validate_card,
)
from .relay import RelayClient
from .store import Store
from . import __version__


THEMES = {
    "Discord": {"bg": "#1e1f22", "panel": "#2b2d31", "tile": "#313338", "hover": "#404249", "accent": "#5865f2", "text": "#f2f3f5", "muted": "#b5bac1", "danger": "#f23f42"},
    "Midnight": {"bg": "#080d18", "panel": "#101827", "tile": "#192439", "hover": "#23334e", "accent": "#69e6b1", "text": "#f4f7fb", "muted": "#91a1b8", "danger": "#ff7b8a"},
    "Graphite": {"bg": "#101112", "panel": "#191b1d", "tile": "#26292c", "hover": "#34383c", "accent": "#82d2ff", "text": "#f3f3f1", "muted": "#a2a6aa", "danger": "#ff8585"},
    "Aubergine": {"bg": "#100b18", "panel": "#1d1429", "tile": "#30203f", "hover": "#452d59", "accent": "#d5a6ff", "text": "#fff8ff", "muted": "#b8a3c7", "danger": "#ff829f"},
    "Forest": {"bg": "#08120f", "panel": "#10201a", "tile": "#193229", "hover": "#24483a", "accent": "#86efac", "text": "#f0fff5", "muted": "#92b5a2", "danger": "#ff8c8c"},
    "Nord": {"bg": "#242933", "panel": "#2e3440", "tile": "#3b4252", "hover": "#434c5e", "accent": "#88c0d0", "text": "#eceff4", "muted": "#aeb8c8", "danger": "#bf616a"},
    "Rose": {"bg": "#160e14", "panel": "#241820", "tile": "#39252f", "hover": "#503342", "accent": "#f2a6bd", "text": "#fff2f6", "muted": "#c6a5b0", "danger": "#ff6f91"},
    "OLED": {"bg": "#000000", "panel": "#090909", "tile": "#171717", "hover": "#252525", "accent": "#7dd3fc", "text": "#ffffff", "muted": "#a3a3a3", "danger": "#fb7185"},
    "Sunset": {"bg": "#140d12", "panel": "#24151c", "tile": "#3b2227", "hover": "#553039", "accent": "#fb923c", "text": "#fff7ed", "muted": "#c9a99a", "danger": "#fb7185"},
    "Custom": {"bg": "#101112", "panel": "#191b1d", "tile": "#26292c", "hover": "#34383c", "accent": "#82d2ff", "text": "#f3f3f1", "muted": "#a2a6aa", "danger": "#ff8585"},
}

PRESENCE_COLORS = {
    "Online": "#23a55a", "Away": "#f0b232",
    "Invisible": "#80848e", "Do Not Disturb": "#f23f43",
}

DEMO_IDENTITY = Identity(
    __import__("hashlib").sha256(b"secure-tiles-demo-encryption-v1").digest(),
    __import__("hashlib").sha256(b"secure-tiles-demo-signing-v1").digest(),
)
DEMO_CARD = validate_card(public_card(DEMO_IDENTITY, "demo_bot"))
UPDATE_API = "https://api.github.com/repos/H0l10W/secure-tiles/releases/latest"
UPDATE_ASSET = "secure-tiles-windows.zip"


def _version_tuple(value: str) -> tuple[int, ...]:
    match = re.fullmatch(r"v?(\d+(?:\.\d+)*)", value.strip())
    return tuple(int(part) for part in match.group(1).split(".")) if match else ()


def _safe_extract_release(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    with zipfile.ZipFile(archive) as bundle:
        members = bundle.infolist()
        if sum(item.file_size for item in members) > 500_000_000:
            raise ValueError("Release is too large to extract safely")
        for item in members:
            target = (destination / item.filename).resolve()
            if target != root and root not in target.parents:
                raise ValueError("Release contains an unsafe path")
        bundle.extractall(destination)


def markdown_html(value: str) -> str:
    """Render the deliberately small, escaped Discord-like Markdown subset."""
    value = html.escape(value)
    pattern = re.compile(r"```(?:\n)?([\s\S]*?)(?:\n)?```|\*\*(.+?)\*\*|(?<!\*)\*([^*\n]+?)\*(?!\*)|`([^`\n]+?)`")
    output: list[str] = []
    position = 0
    for match in pattern.finditer(value):
        output.append(value[position:match.start()].replace("\n", "<br>"))
        if match.group(1) is not None:
            output.append(f'<pre style="background:#202225;padding:8px">{match.group(1)}</pre>')
        elif match.group(2) is not None:
            output.append(f"<b>{match.group(2)}</b>")
        elif match.group(3) is not None:
            output.append(f"<i>{match.group(3)}</i>")
        else:
            output.append(f'<code style="background:#202225">{match.group(4)}</code>')
        position = match.end()
    output.append(value[position:].replace("\n", "<br>"))
    return "".join(output)


class Controller(QObject):
    changed = Signal()
    jobFinished = Signal(object, object, object)

    def __init__(self, application: QApplication):
        super().__init__()
        self.application = application
        data_root = Path(os.environ.get("SECURE_TILES_DATA_DIR", Path.home() / ".secure_tiles"))
        self.store = Store(data_root)
        self.preferences = self.store.preferences()
        self.vault = self.store.load_vault()
        self.identity: Identity | None = None
        self.relay_url = str((self.vault or {}).get("relay", "http://127.0.0.1:8765"))
        self.relay = RelayClient(self.relay_url)
        self.local_relay = None
        self._closing = False
        self._page = "auth"
        self._settings_tab = "My Profile"
        self._selected: dict[str, str] | None = None
        self._status = ""
        self._relay_status = "Connecting..."
        self._busy = False
        self._update_status = ""
        self._update_version = ""
        self._update_stage = ""
        self._checking_updates = False
        self._sidebar_expanded = bool(self.preferences.get("sidebar_expanded", True)) if bool(self.preferences.get("remember_sidebar", True)) else True
        self.jobFinished.connect(self._finish_job)
        if bool(self.preferences.get("auto_start_relay", True)):
            self._ensure_local_relay()
        self.poll_timer = QTimer(self)
        self.poll_timer.setInterval(2500)
        self.poll_timer.timeout.connect(self.poll_inbox)
        if bool(self.preferences.get("auto_check_updates", True)):
            QTimer.singleShot(2500, self.checkForUpdates)

    def _notify(self) -> None:
        self.changed.emit()

    @Property(bool, notify=changed)
    def hasVault(self): return self.vault is not None

    @Property(str, notify=changed)
    def vaultName(self): return str((self.vault or {}).get("name", "user"))

    @Property(str, notify=changed)
    def username(self): return str((self.vault or {}).get("name", ""))

    @Property(str, notify=changed)
    def page(self): return self._page

    @Property(str, notify=changed)
    def settingsTab(self): return self._settings_tab

    @Property(str, notify=changed)
    def status(self): return self._status

    @Property(str, notify=changed)
    def relayStatus(self): return self._relay_status

    @Property(bool, notify=changed)
    def busy(self): return self._busy

    @Property(bool, notify=changed)
    def sidebarExpanded(self): return self._sidebar_expanded

    @Property('QVariantMap', notify=changed)
    def colors(self):
        name = str(self.preferences.get("theme", "Midnight"))
        colors = dict(THEMES.get(name, THEMES["Midnight"]))
        if name == "Custom": colors["accent"] = str(self.preferences.get("custom_accent", colors["accent"]))
        return colors

    @Property(str, notify=changed)
    def themeName(self): return str(self.preferences.get("theme", "Midnight"))

    @Property('QVariantList', notify=changed)
    def themeOptions(self):
        return [{"name": name, "accent": str(self.preferences.get("custom_accent", colors["accent"])) if name == "Custom" else colors["accent"]} for name, colors in THEMES.items()]

    @Property('QVariantList', notify=changed)
    def contacts(self):
        metadata = self.preferences.get("contact_metadata", {})
        result = []
        for card in self.store.contacts():
            meta = metadata.get(card["signing_key"], {}) if isinstance(metadata, dict) else {}
            result.append({**card, "initials": "BOT" if card["signing_key"] == DEMO_CARD["signing_key"] else card["name"][:2].upper(),
                           "displayName": str(meta.get("nickname", "")).strip() or card["name"], "favorite": bool(meta.get("favorite", False))})
        return sorted(result, key=lambda card: (not card["favorite"], card["displayName"].lower()))

    @Property(str, notify=changed)
    def selectedName(self): return self._selected["name"] if self._selected else ""

    def _selected_metadata(self):
        if not self._selected: return {}
        values = self.preferences.get("contact_metadata", {})
        return values.get(self._selected["signing_key"], {}) if isinstance(values, dict) else {}

    @Property(str, notify=changed)
    def selectedDisplayName(self): return str(self._selected_metadata().get("nickname", "")).strip() or self.selectedName

    @Property(str, notify=changed)
    def selectedNickname(self): return str(self._selected_metadata().get("nickname", ""))

    @Property(bool, notify=changed)
    def selectedFavorite(self): return bool(self._selected_metadata().get("favorite", False))

    @Property(str, notify=changed)
    def selectedSigningKey(self): return self._selected["signing_key"] if self._selected else ""

    @Property(str, notify=changed)
    def safetyNumber(self): return fingerprint(self._selected["signing_key"]) if self._selected else ""

    @Property(bool, notify=changed)
    def selectedIsDemo(self): return bool(self._selected and self._selected["signing_key"] == DEMO_CARD["signing_key"])

    @Property('QVariantList', notify=changed)
    def messages(self):
        if not self._selected: return []
        result = []
        use_24_hour = bool(self.preferences.get("use_24_hour_time", True))
        show_content = bool(self.preferences.get("message_previews", True))
        previous_date = None
        for row in self.store.messages(self._selected["signing_key"]):
            stamp = datetime.fromtimestamp(row["sent_at"])
            date_key = stamp.date()
            result.append({
                "sender": "YOU" if row["direction"] == "out" else self.selectedDisplayName,
                "plainText": row["plaintext"] if show_content else "", "body": markdown_html(row["plaintext"]) if show_content else "<i>Message content hidden by Privacy settings.</i>",
                "timestamp": stamp.strftime("%H:%M" if use_24_hour else "%I:%M %p").lstrip("0"),
                "fullTimestamp": stamp.strftime("%d %B %Y at %H:%M" if use_24_hour else "%d %B %Y at %I:%M %p"),
                "showDate": date_key != previous_date,
                "dateLabel": stamp.strftime("%A, %d %B %Y"),
                "outgoing": row["direction"] == "out",
            })
            previous_date = date_key
        return result

    @Property(str, notify=changed)
    def displayName(self): return str(self.preferences.get("display_name", self.username))

    @Property(str, notify=changed)
    def customStatus(self): return str(self.preferences.get("custom_status", ""))

    @Property(str, notify=changed)
    def bio(self): return str(self.preferences.get("bio", ""))

    @Property(str, notify=changed)
    def pronouns(self): return str(self.preferences.get("pronouns", ""))

    @Property(str, notify=changed)
    def statusEmoji(self): return str(self.preferences.get("status_emoji", ""))

    @Property(str, notify=changed)
    def bannerColor(self): return str(self.preferences.get("banner_color", self.colors["accent"]))

    @Property(str, notify=changed)
    def presence(self): return str(self.preferences.get("presence", "Online"))

    @Property(str, notify=changed)
    def presenceColor(self): return PRESENCE_COLORS.get(self.presence, PRESENCE_COLORS["Invisible"])

    @Property(str, notify=changed)
    def avatarUrl(self):
        path = str(self.preferences.get("avatar", ""))
        return QUrl.fromLocalFile(path).toString() if path and Path(path).is_file() else ""

    @Property(bool, notify=changed)
    def animationsEnabled(self): return bool(self.preferences.get("animations", True))

    @Property(float, notify=changed)
    def fontScale(self):
        try: return max(.85, min(1.25, float(self.preferences.get("font_scale", 1.0))))
        except (TypeError, ValueError): return 1.0

    @Property(str, notify=changed)
    def messageDensity(self):
        value = str(self.preferences.get("message_density", "Cozy"))
        return value if value in {"Cozy", "Compact"} else "Cozy"

    @Property(bool, notify=changed)
    def enterToSend(self): return bool(self.preferences.get("enter_to_send", True))

    @Property(int, notify=changed)
    def cornerRadius(self): return {"Compact": 6, "Soft": 10, "Rounded": 16}.get(str(self.preferences.get("corner_style", "Soft")), 10)

    @Property(str, notify=changed)
    def cornerStyle(self): return str(self.preferences.get("corner_style", "Soft"))

    @Property(str, notify=changed)
    def chatBackground(self): return str(self.preferences.get("chat_background", self.colors["panel"]))

    @Property(str, notify=changed)
    def relayUrl(self): return self.relay_url

    @Property(str, notify=changed)
    def dataLocation(self): return str(self.store.root)

    @Property(str, constant=True)
    def appVersion(self): return __version__

    @Property(str, notify=changed)
    def updateStatus(self): return self._update_status

    @Property(str, notify=changed)
    def updateVersion(self): return self._update_version

    @Property(bool, notify=changed)
    def updateReady(self): return bool(self._update_stage)

    @Property(bool, notify=changed)
    def checkingUpdates(self): return self._checking_updates

    @Property('QVariantMap', notify=changed)
    def settings(self): return self.preferences

    @Slot(str, str)
    def unlock(self, passphrase: str, _unused: str = ""):
        try:
            self.identity = unlock_identity(self.vault or {}, passphrase)
            self.relay = RelayClient(self.relay_url)
            self._enter_messenger()
        except CryptoError as exc:
            self._status = str(exc); self._notify()

    @Slot(str, str, str)
    def signup(self, username: str, passphrase: str, relay_url: str):
        name = username.strip().lower()
        if not re.fullmatch(r"[a-zA-Z0-9_]{1,32}", name):
            self._status = "Use 1-32 letters, numbers, or underscores."; self._notify(); return
        try:
            identity = Identity.generate(); locked = lock_identity(identity, passphrase)
        except CryptoError as exc:
            self._status = str(exc); self._notify(); return
        chosen_relay = relay_url.strip() or self.relay_url
        client = RelayClient(chosen_relay)
        self._status = "Creating identity and claiming username..."; self._busy = True; self._notify()
        def complete(_result, error):
            self._busy = False
            if error:
                self._status = str(error); self._notify(); return
            locked.update({"name": name, "relay": chosen_relay})
            self.store.save_vault(locked)
            self.vault, self.identity, self.relay_url, self.relay = locked, identity, chosen_relay, client
            self._enter_messenger()
        self.run_job(lambda: client.register(public_card(identity, name)), complete)

    def _enter_messenger(self):
        self.store.add_contact(DEMO_CARD)
        self._page = "chat"; self._status = ""; self._relay_status = "Connecting..."
        self.poll_timer.start(); self.poll_inbox(); self._notify()

    @Slot(str)
    def openPage(self, page: str): self._page = page; self._notify()

    @Slot(str)
    def openSettingsTab(self, tab: str): self._settings_tab = tab; self._page = "settings"; self._notify()

    @Slot()
    def toggleSidebar(self):
        self._sidebar_expanded = not self._sidebar_expanded
        if bool(self.preferences.get("remember_sidebar", True)):
            self._save_preferences(sidebar_expanded=self._sidebar_expanded)
        else:
            self._notify()

    @Slot(str)
    def selectContact(self, signing_key: str):
        self._selected = next((c for c in self.store.contacts() if c["signing_key"] == signing_key), None)
        self._page = "chat"; self._notify()

    @Slot(str)
    def addContact(self, value: str):
        username = value.strip().lower().lstrip("@")
        if not re.fullmatch(r"[a-zA-Z0-9_]{1,32}", username):
            self._status = "Enter a valid username."; self._notify(); return
        self._status = f"Finding @{username}..."; self._notify()
        def complete(result, error):
            if error: self._status = str(error); self._notify(); return
            try:
                card = validate_card(result)
                existing = self.store.contact_by_name(username)
                if existing and existing["signing_key"] != card["signing_key"]:
                    raise CryptoError("SECURITY WARNING: this username's identity key changed.")
                self.store.add_contact(card); self._selected = card
                self._status = f"@{username} added and identity pinned."
            except CryptoError as exc: self._status = str(exc)
            self._notify()
        self.run_job(lambda: self.relay.lookup(username), complete)

    @Slot(str)
    def sendMessage(self, text: str):
        text = text.strip()
        if not self._selected or not text: return
        if len(text) > 4000:
            self._status = "Messages are limited to 4,000 characters."; self._notify(); return
        try: packet = encrypt_message(self.identity, self._selected, text)  # type: ignore[arg-type]
        except CryptoError as exc: self._status = str(exc); self._notify(); return
        contact = self._selected
        self._status = "Sending encrypted packet..."; self._notify()
        def delivered(_result, error):
            if error: self._status = f"Not sent: {error}"; self._notify(); return
            self.store.add_message(packet["id"], contact["signing_key"], "out", int(time.time()), text)
            self._status = "Delivered to encrypted relay."; self._notify()
        if contact["signing_key"] != DEMO_CARD["signing_key"]:
            self.run_job(lambda: self.relay.send(packet), delivered); return
        def demo_reply():
            time.sleep(.2)
            received = decrypt_message(DEMO_IDENTITY, packet, public_card(self.identity, self.username))  # type: ignore[arg-type]
            return encrypt_message(DEMO_IDENTITY, public_card(self.identity, self.username), f"Encrypted echo: {received['text']}")  # type: ignore[arg-type]
        def demo_complete(response, error):
            delivered(None, error)
            if error: return
            message = decrypt_message(self.identity, response, DEMO_CARD)  # type: ignore[arg-type]
            self.store.add_message(message["id"], DEMO_CARD["signing_key"], "in", message["sent_at"], message["text"])
            self._notify()
        self.run_job(demo_reply, demo_complete)

    @Slot(str, str, str, str, str, str)
    def saveProfile(self, display_name: str, custom_status: str, bio: str, pronouns: str, banner_color: str, status_emoji: str):
        self._save_preferences(display_name=display_name.strip()[:32] or self.username,
                               custom_status=custom_status.strip()[:80], bio=bio.strip()[:190],
                               pronouns=pronouns.strip()[:40], banner_color=banner_color, status_emoji=status_emoji.strip()[:8])
        self._status = "Profile saved."; self._notify()

    @Slot(str)
    def setPresence(self, value: str):
        if value in PRESENCE_COLORS: self._save_preferences(presence=value)

    @Slot(str)
    def setTheme(self, value: str):
        if value in THEMES: self._save_preferences(theme=value)

    @Slot()
    def chooseCustomAccent(self):
        color = QColorDialog.getColor(QColor(str(self.preferences.get("custom_accent", "#82d2ff"))), None, "Choose interface accent")
        if color.isValid(): self._save_preferences(theme="Custom", custom_accent=color.name())

    @Slot()
    def chooseBannerColor(self):
        color = QColorDialog.getColor(QColor(self.bannerColor), None, "Choose profile banner color")
        if color.isValid(): self._save_preferences(banner_color=color.name())

    @Slot()
    def chooseChatBackground(self):
        color = QColorDialog.getColor(QColor(self.chatBackground), None, "Choose conversation background")
        if color.isValid(): self._save_preferences(chat_background=color.name())

    @Slot()
    def resetChatBackground(self):
        self.preferences.pop("chat_background", None); self.store.save_preferences(self.preferences); self._notify()

    @Slot(float)
    def setFontScale(self, value: float): self._save_preferences(font_scale=max(.85, min(1.25, value)))

    @Slot(str)
    def setMessageDensity(self, value: str):
        if value in {"Cozy", "Compact"}: self._save_preferences(message_density=value)

    @Slot(str)
    def setCornerStyle(self, value: str):
        if value in {"Compact", "Soft", "Rounded"}: self._save_preferences(corner_style=value)

    def _update_contact_metadata(self, **values):
        if not self._selected: return
        metadata = dict(self.preferences.get("contact_metadata", {}))
        current = dict(metadata.get(self._selected["signing_key"], {})); current.update(values)
        metadata[self._selected["signing_key"]] = current
        self._save_preferences(contact_metadata=metadata)

    @Slot(str)
    def setContactNickname(self, value: str): self._update_contact_metadata(nickname=value.strip()[:32])

    @Slot()
    def toggleFavoriteContact(self): self._update_contact_metadata(favorite=not self.selectedFavorite)

    @Slot(str)
    def copyText(self, value: str):
        self.application.clipboard().setText(value)
        self._status = "Message copied to clipboard."; self._notify()

    @Slot()
    def checkForUpdates(self):
        if self._checking_updates or self._update_stage or self._closing: return
        self._checking_updates = True; self._update_status = "Checking for updates..."; self._notify()
        def work():
            request = urllib.request.Request(UPDATE_API, headers={
                "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2026-03-10",
                "User-Agent": f"SecureTiles/{__version__}",
            })
            try:
                with urllib.request.urlopen(request, timeout=12) as response:
                    release = json.loads(response.read().decode("utf-8"))
            except urllib.error.HTTPError as exc:
                if exc.code == 404: return {"state": "none"}
                raise
            version = str(release.get("tag_name", "")).lstrip("v")
            if not _version_tuple(version) or _version_tuple(version) <= _version_tuple(__version__):
                return {"state": "current"}
            asset = next((item for item in release.get("assets", []) if item.get("name") == UPDATE_ASSET), None)
            if not asset: raise ValueError(f"Release v{version} has no {UPDATE_ASSET} asset")
            digest = str(asset.get("digest", ""))
            if not digest.startswith("sha256:"):
                raise ValueError("Release asset has no GitHub SHA-256 digest")
            updates = self.store.root / "updates"; updates.mkdir(parents=True, exist_ok=True)
            archive = updates / f"secure-tiles-{version}.zip.part"
            download = urllib.request.Request(str(asset["browser_download_url"]), headers={"User-Agent": f"SecureTiles/{__version__}"})
            hasher = hashlib.sha256(); size = 0
            with urllib.request.urlopen(download, timeout=30) as response, archive.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    size += len(chunk)
                    if size > 250_000_000: raise ValueError("Release download exceeds the size limit")
                    hasher.update(chunk); output.write(chunk)
            if hasher.hexdigest().lower() != digest.split(":", 1)[1].lower():
                archive.unlink(missing_ok=True); raise ValueError("Downloaded update failed SHA-256 verification")
            stage = updates / f"v{version}"
            if stage.exists():
                import shutil
                shutil.rmtree(stage)
            _safe_extract_release(archive, stage); archive.unlink(missing_ok=True)
            if not (stage / "main.py").is_file() or not (stage / "secure_tiles").is_dir():
                raise ValueError("Release package is incomplete")
            return {"state": "ready", "version": version, "stage": str(stage)}
        def complete(result, error):
            self._checking_updates = False
            if error: self._update_status = f"Update check failed: {error}"
            elif result["state"] == "none": self._update_status = "No published releases are available yet."
            elif result["state"] == "current": self._update_status = f"Secure Tiles {__version__} is up to date."
            else:
                self._update_version, self._update_stage = result["version"], result["stage"]
                self._update_status = f"Version {self._update_version} is downloaded and ready."
            self._notify()
        self.run_job(work, complete)

    @Slot()
    def restartToUpdate(self):
        if not self._update_stage: return
        target = Path(__file__).resolve().parents[1]
        command = [sys.executable, "-m", "secure_tiles.updater", "--stage", self._update_stage,
                   "--target", str(target), "--pid", str(os.getpid()), "--version", self._update_version]
        flags = 0
        if os.name == "nt": flags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
        subprocess.Popen(command, cwd=str(target), creationflags=flags, close_fds=True)
        self.application.quit()

    @Slot(str, bool)
    def setPreference(self, key: str, value: bool):
        self._save_preferences(**{key: value})
        if key == "auto_start_relay" and value and self.local_relay is None: self._ensure_local_relay()

    @Slot()
    def chooseAvatar(self):
        filename, _ = QFileDialog.getOpenFileName(None, "Choose profile picture", "", "Images (*.png *.jpg *.jpeg *.webp)")
        if not filename: return
        try:
            self.store.save_avatar(Path(filename)); self.preferences = self.store.preferences(); self._status = "Profile picture saved."
        except (OSError, ValueError) as exc: self._status = f"Could not use that image: {exc}"
        self._notify()

    def poll_inbox(self):
        if not self.identity or self._closing: return
        identity = self.identity
        def complete(packets, error):
            if self._closing: return
            if error: self._relay_status = "Relay offline"
            else:
                self._relay_status = "Relay connected"
                for envelope in packets or []:
                    sender = self.store.contact_by_encryption_key(str(envelope.get("from", "")))
                    if not sender: continue
                    try:
                        message = decrypt_message(identity, envelope, sender)
                        self.store.add_message(message["id"], sender["signing_key"], "in", message["sent_at"], message["text"])
                    except CryptoError: pass
            self._notify()
        self.run_job(lambda: self.relay.inbox(identity.encryption_public), complete)

    def _save_preferences(self, **values):
        self.preferences.update(values); self.store.save_preferences(self.preferences); self._notify()

    def run_job(self, work: Callable, callback: Callable):
        def runner():
            try: result, error = work(), None
            except Exception as exc: result, error = None, exc
            if not self._closing: self.jobFinished.emit(callback, result, error)
        threading.Thread(target=runner, name="secure-tiles-worker", daemon=True).start()

    @Slot(object, object, object)
    def _finish_job(self, callback, result, error): callback(result, error)

    def _ensure_local_relay(self):
        parsed = urlparse(self.relay_url)
        if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}: return
        port = parsed.port or 80
        try:
            with socket.create_connection((parsed.hostname, port), timeout=.25): return
        except OSError: pass
        try:
            from http.server import ThreadingHTTPServer
            from relay_server import Database, Handler
            class EmbeddedHandler(Handler): pass
            EmbeddedHandler.db = Database(self.store.root / "relay.db")
            self.local_relay = ThreadingHTTPServer((parsed.hostname, port), EmbeddedHandler)
            threading.Thread(target=self.local_relay.serve_forever, name="secure-tiles-relay", daemon=True).start()
        except OSError: self.local_relay = None

    def shutdown(self):
        if self._closing: return
        self._closing = True; self.poll_timer.stop()
        try: self.store.db.close()
        except sqlite3.Error: pass
        if self.local_relay:
            relay = self.local_relay
            def stop():
                try: relay.shutdown(); relay.server_close(); relay.RequestHandlerClass.db.connection.close()
                except (OSError, sqlite3.Error): pass
            threading.Thread(target=stop, name="secure-tiles-relay-shutdown", daemon=True).start()


def main():
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    QGuiApplication.setApplicationName("Secure Tiles")
    QGuiApplication.setOrganizationName("Secure Tiles")
    application = QApplication(sys.argv)
    icon = Path(__file__).resolve().parents[1] / "assets" / "secure_tiles.ico"
    if icon.exists(): application.setWindowIcon(QIcon(str(icon)))
    controller = Controller(application)
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", controller)
    qml = Path(__file__).resolve().parent / "qml" / "Main.qml"
    engine.load(QUrl.fromLocalFile(str(qml)))
    if not engine.rootObjects():
        controller.shutdown(); raise RuntimeError(f"Could not load {qml}")
    window = engine.rootObjects()[0]
    width = max(880, min(3840, int(controller.preferences.get("window_width", 1100))))
    height = max(580, min(2160, int(controller.preferences.get("window_height", 720))))
    window.setWidth(width); window.setHeight(height)
    def closing():
        controller._save_preferences(window_width=window.width(), window_height=window.height())
        controller.shutdown()
    application.aboutToQuit.connect(closing)
    sys.exit(application.exec())
