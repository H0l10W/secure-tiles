from __future__ import annotations

import html
import base64
import hashlib
import json
import mimetypes
import os
import re
import shutil
import socket
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
import zipfile
from datetime import datetime
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlparse

from PySide6.QtCore import QBuffer, QByteArray, QIODevice, QObject, Property, QRect, Qt, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QColor, QFont, QGuiApplication, QIcon, QImage, QWindow
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication, QColorDialog, QFileDialog
from nacl import secret, utils

from .crypto import (
    CryptoError, Identity, decrypt_message, encrypt_message, fingerprint,
    lock_identity, public_card, unlock_identity, validate_card,
)
from .relay import RelayClient
from .store import Store
from .servers import PERMISSIONS, new_server_id, sign_server_action
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
DEMO_PROFILE = {
    "display_name": "Cipher Bot", "display_font": "Consolas",
    "custom_status": "Testing encrypted profile cards", "status_emoji": "BOT",
    "bio": "I am the built-in echo bot. Message me to test encrypted chats and profile styling.",
    "pronouns": "bot/bot", "banner_color": "#7c3aed",
}
UPDATE_API = "https://api.github.com/repos/H0l10W/nightseal/releases/latest"
DEFAULT_RELAY_URL = "https://secure-tiles-relay.secure-tiles-cloudflare-relay.workers.dev"
ATTACHMENT_CHUNK_SIZE = 1024 * 1024
TYPING_SIGNAL_PREFIX = "\0secure-tiles-typing:"
PRESENCE_SIGNAL_PREFIX = "\0secure-tiles-presence:"
PROFILE_SIGNAL_PREFIX = "\0secure-tiles-profile:"
SERVER_MESSAGE_PREFIX = "\0secure-tiles-server:"
SERVER_INVITE_PREFIX = "\0secure-tiles-invite:"
DISPLAY_FONTS = ("Segoe UI", "Bahnschrift", "Georgia", "Trebuchet MS", "Consolas")
DISPLAY_FONT_OPTIONS = (
    {"name": "Modern", "family": "Segoe UI"},
    {"name": "Heavy Metal", "family": "Bahnschrift"},
    {"name": "Vampire", "family": "Georgia"},
    {"name": "Arcade", "family": "Trebuchet MS"},
    {"name": "Cipher", "family": "Consolas"},
)


def _profile_image_data(path: Path) -> str:
    """Return a small profile-card preview that fits inside an encrypted signal."""
    image = QImage(str(path))
    if image.isNull(): return ""
    image = image.scaled(320, 180, Qt.KeepAspectRatio, Qt.SmoothTransformation)
    for quality in (72, 58, 44, 32):
        encoded = QByteArray(); buffer = QBuffer(encoded); buffer.open(QIODevice.WriteOnly)
        image.save(buffer, "JPG", quality); buffer.close()
        if len(encoded) <= 14_000:
            return "data:image/jpeg;base64," + base64.b64encode(bytes(encoded)).decode("ascii")
    return ""


def _version_tuple(value: str) -> tuple[int, ...]:
    match = re.fullmatch(r"v?(\d+(?:\.\d+)*)", value.strip())
    return tuple(int(part) for part in match.group(1).split(".")) if match else ()


def _release_asset_name(version: str, installed: bool) -> str:
    kind = "Setup" if installed else "Portable"
    return f"Nightseal-{kind}-v{version}.exe"


def _update_apply_script(mode: str) -> str:
    if mode == "installer":
        return """param([int]$ParentProcessId, [string]$Package, [string]$Target, [string]$Log)
$ErrorActionPreference = 'Stop'
function Write-UpdateLog([string]$Message) { if ($Log) { Add-Content -LiteralPath $Log -Value "$(Get-Date -Format o) $Message" -Encoding UTF8 } }
try {
    Write-UpdateLog "Waiting for parent $ParentProcessId"
    Wait-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
    Write-UpdateLog "Starting installer $Package"
    $installer = Start-Process -FilePath $Package -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/CLOSEAPPLICATIONS') -Wait -PassThru
    if ($installer.ExitCode -ne 0) { throw "Installer exited with code $($installer.ExitCode)" }
    for ($attempt = 0; $attempt -lt 120 -and -not (Test-Path -LiteralPath $Target); $attempt++) { Start-Sleep -Milliseconds 500 }
    if (-not (Test-Path -LiteralPath $Target)) { throw "Installed executable was not found at $Target" }
    Write-UpdateLog "Relaunching $Target"
    [Environment]::SetEnvironmentVariable('PYINSTALLER_RESET_ENVIRONMENT', '1', 'Process')
    Start-Process -FilePath $Target -WorkingDirectory (Split-Path -Parent $Target)
    Remove-Item -LiteralPath $Package -Force -ErrorAction SilentlyContinue
    Write-UpdateLog 'Update completed'
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
} catch {
    Write-UpdateLog "FAILED: $($_.Exception.Message)"
    exit 1
}
"""
    return """param([int]$ParentProcessId, [string]$Package, [string]$Target, [string]$Log)
$ErrorActionPreference = 'Stop'
function Write-UpdateLog([string]$Message) { if ($Log) { Add-Content -LiteralPath $Log -Value "$(Get-Date -Format o) $Message" -Encoding UTF8 } }
try {
    Write-UpdateLog "Waiting for parent $ParentProcessId"
    Wait-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
    $moved = $false
    for ($attempt = 0; $attempt -lt 120 -and -not $moved; $attempt++) {
        try { Move-Item -LiteralPath $Package -Destination $Target -Force -ErrorAction Stop; $moved = $true }
        catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $moved) { throw "Could not replace $Target" }
    Write-UpdateLog "Relaunching $Target"
    [Environment]::SetEnvironmentVariable('PYINSTALLER_RESET_ENVIRONMENT', '1', 'Process')
    Start-Process -FilePath $Target -WorkingDirectory (Split-Path -Parent $Target)
    Write-UpdateLog 'Update completed'
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
} catch {
    Write-UpdateLog "FAILED: $($_.Exception.Message)"
    exit 1
}
"""


def _spawn_update_helper(command: list[str], cwd: Path) -> subprocess.Popen:
    flags = 0
    if os.name == "nt": flags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
    return subprocess.Popen(command, cwd=str(cwd), creationflags=flags, close_fds=False)


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
    transferProgress = Signal(str)

    def __init__(self, application: QApplication):
        super().__init__()
        self.application = application
        data_root = Path(os.environ.get("SECURE_TILES_DATA_DIR", Path.home() / ".secure_tiles"))
        self.store = Store(data_root)
        self.preferences = self.store.preferences()
        self.vault = self.store.load_vault()
        self.identity: Identity | None = None
        stored_relay = str((self.vault or {}).get("relay", DEFAULT_RELAY_URL))
        self._migrate_relay = bool(self.vault and urlparse(stored_relay).hostname in {"127.0.0.1", "localhost", "::1"})
        self.relay_url = DEFAULT_RELAY_URL if self._migrate_relay else stored_relay
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
        self._update_mode = ""
        self._checking_updates = False
        self._pending_attachments: list[dict[str, Any]] = []
        self._sending = False
        self._polling = False
        self._typing_active = False
        self._typing_contacts: set[str] = set()
        self._presence_contacts: dict[str, str] = {}
        self._remote_profiles: dict[str, dict[str, Any]] = dict(self.preferences.get("remote_profiles", {}))
        stored_unread = self.preferences.get("unread_counts", {})
        self._unread_counts: dict[str, int] = {
            str(key): max(0, int(value)) for key, value in stored_unread.items()
        } if isinstance(stored_unread, dict) else {}
        self._sidebar_expanded = bool(self.preferences.get("sidebar_expanded", True)) if bool(self.preferences.get("remember_sidebar", True)) else True
        self._sidebar_width = max(230, min(420, int(self.preferences.get("sidebar_width", 276))))
        self._server_channel_width = max(150, min(360, int(self.preferences.get("server_channel_width", 220))))
        self._server_member_width = max(170, min(360, int(self.preferences.get("server_member_width", 240))))
        collapsed = self.preferences.get("collapsed_server_categories", {})
        self._collapsed_server_categories: dict[str, bool] = dict(collapsed) if isinstance(collapsed, dict) else {}
        self._servers: list[dict[str, Any]] = []
        self._selected_server_id = ""
        self._selected_channel_id = ""
        self.jobFinished.connect(self._finish_job)
        self.transferProgress.connect(self._set_transfer_status)
        if bool(self.preferences.get("auto_start_relay", True)):
            self._ensure_local_relay()
        self.poll_timer = QTimer(self)
        self.poll_timer.setInterval(500)
        self.poll_timer.timeout.connect(self.poll_inbox)
        self.typing_timer = QTimer(self)
        self.typing_timer.setInterval(1800)
        self.typing_timer.timeout.connect(self._refresh_typing)
        self.presence_timer = QTimer(self)
        self.presence_timer.setInterval(20_000)
        self.presence_timer.timeout.connect(self._publish_presence)
        if bool(self.preferences.get("auto_check_updates", True)):
            QTimer.singleShot(2500, self.checkForUpdates)

    def _notify(self) -> None:
        self.changed.emit()

    @Slot(str)
    def _set_transfer_status(self, value: str) -> None:
        self._status = value; self._notify()

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

    @Property(int, notify=changed)
    def sidebarWidth(self): return self._sidebar_width

    @Property(int, notify=changed)
    def serverChannelWidth(self): return self._server_channel_width

    @Property(int, notify=changed)
    def serverMemberWidth(self): return self._server_member_width

    @Property('QVariantMap', notify=changed)
    def colors(self):
        name = str(self.preferences.get("theme", "Midnight"))
        colors = dict(THEMES.get(name, THEMES["Midnight"]))
        if name == "Custom":
            colors["accent"] = str(self.preferences.get("custom_accent", colors["accent"]))
            colors["bg"] = str(self.preferences.get("custom_background", colors["bg"]))
        return colors

    @Property('QVariantMap', notify=changed)
    def qmlColors(self):
        return {name: QColor(value) for name, value in self.colors.items()}

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
            remote = self._remote_profiles.get(card["signing_key"], {})
            result.append({**card, "initials": "BOT" if card["signing_key"] == DEMO_CARD["signing_key"] else card["name"][:2].upper(),
                           "displayName": str(meta.get("nickname", "")).strip() or str(remote.get("display_name", "")).strip() or card["name"],
                           "displayFont": str(remote.get("display_font", "Segoe UI")), "favorite": bool(meta.get("favorite", False)),
                           "presence": "Online" if card["signing_key"] == DEMO_CARD["signing_key"] else self._presence_contacts.get(card["signing_key"], "Offline"),
                           "unread": self._unread_counts.get(card["signing_key"], 0)})
        return sorted(result, key=lambda card: (not card["favorite"], card["displayName"].lower()))

    @Property('QVariantList', notify=changed)
    def favoriteContacts(self): return [card for card in self.contacts if card["favorite"]]

    @Property('QVariantList', notify=changed)
    def invitableContacts(self): return [card for card in self.contacts if card["signing_key"] != DEMO_CARD["signing_key"]]

    @Property('QVariantList', notify=changed)
    def receivedServerInvites(self):
        now = int(time.time()); values = self.preferences.get("received_server_invites", [])
        return [item for item in values if isinstance(item, dict) and (not int(item.get("expires", 0)) or int(item["expires"]) >= now)]

    @Property('QVariantList', notify=changed)
    def servers(self): return self._servers

    @Property('QVariantList', notify=changed)
    def serverRailItems(self):
        layout = self.preferences.get("server_layout", [])
        known = {server["id"]: server for server in self._servers}; result, placed = [], set()
        if isinstance(layout, list):
            for item in layout:
                if not isinstance(item, dict): continue
                if item.get("type") == "folder":
                    children = [known[value] for value in item.get("servers", []) if value in known and value not in placed]
                    if children:
                        folder_id = str(item.get("id", ""))
                        result.append({"type": "folder", "id": folder_id, "name": str(item.get("name", "Folder")), "color": str(item.get("color", "#5865f2")), "icon": str(item.get("icon", "")), "servers": children,
                                       "expanded": folder_id in self.preferences.get("expanded_server_folders", [])})
                        placed.update(server["id"] for server in children)
                elif item.get("id") in known and item["id"] not in placed:
                    result.append({"type": "server", **known[item["id"]]}); placed.add(item["id"])
        result.extend({"type": "server", **server} for server in self._servers if server["id"] not in placed)
        return result

    @Property('QVariantList', constant=True)
    def serverPermissions(self): return list(PERMISSIONS)

    @Property(str, notify=changed)
    def selectedServerId(self): return self._selected_server_id

    @Property('QVariantMap', notify=changed)
    def selectedServer(self): return next((server for server in self._servers if server["id"] == self._selected_server_id), {})

    @Property(bool, notify=changed)
    def selectedServerOwned(self): return bool(self.identity and self.selectedServer.get("owner_key") == self.identity.signing_public)

    @Property(str, notify=changed)
    def selectedChannelId(self): return self._selected_channel_id

    @Property('QVariantMap', notify=changed)
    def selectedChannel(self):
        return next((channel for channel in self.selectedServer.get("channels", []) if channel["id"] == self._selected_channel_id), {})

    @Property('QVariantList', notify=changed)
    def serverChannelGroups(self):
        channels = self.selectedServer.get("channels", [])
        categories = [channel for channel in channels if channel.get("type") == "category" or (channel.get("type") == "voice" and channel.get("topic") == "category")]
        text_channels = [channel for channel in channels if channel.get("type") == "text"]
        groups = [{"id": "", "name": "Text channels", "category": False,
                   "collapsed": False, "channels": [channel for channel in text_channels if not str(channel.get("topic", "")).startswith("category:")] }]
        for category in categories:
            category_id = str(category["id"])
            groups.append({"id": category_id, "name": category["name"], "category": True,
                           "collapsed": bool(self._collapsed_server_categories.get(f"{self._selected_server_id}:{category_id}", False)),
                           "channels": [channel for channel in text_channels if channel.get("topic") == f"category:{category_id}"]})
        return groups

    @Property('QVariantList', notify=changed)
    def serverMessages(self):
        if not self._selected_server_id or not self._selected_channel_id: return []
        members = {member["signing_key"]: member for member in self.selectedServer.get("members", [])}
        result = []
        for row in self.store.server_messages(self._selected_server_id, self._selected_channel_id):
            card = members.get(row["sender_key"], {}).get("card", {})
            name = self.displayName if row["direction"] == "out" else card.get("name", "Member")
            result.append({"id": row["id"], "sender": name, "text": row["plaintext"],
                           "outgoing": row["direction"] == "out",
                           "timestamp": datetime.fromtimestamp(row["sent_at"]).strftime("%H:%M")})
        return result

    @Property('QVariantList', notify=changed)
    def serverMemberGroups(self):
        server = self.selectedServer
        roles = sorted(server.get("roles", []), key=lambda role: int(role.get("position", 0)))
        role_by_id = {role["id"]: role for role in roles}
        grouped: dict[str, list[dict[str, Any]]] = {role["id"]: [] for role in roles}; offline = []
        for member in server.get("members", []):
            card = member.get("card", {}); signing_key = str(member.get("signing_key", ""))
            status = "Online" if self.identity and signing_key == self.identity.signing_public else self._presence_contacts.get(signing_key, "Offline")
            remote = self._remote_profiles.get(signing_key, {})
            value = {"signing_key": signing_key, "name": str(remote.get("display_name", "")).strip() or card.get("name", "Member"),
                     "username": card.get("name", "member"), "status": status, "initials": str(card.get("name", "M"))[:2].upper()}
            if status == "Offline": offline.append(value); continue
            role_id = next((value for value in member.get("roles", []) if value in role_by_id), "member")
            grouped.setdefault(role_id, []).append(value)
        result = [{"id": role["id"], "name": role["name"], "color": role.get("color", self.colors["muted"]), "members": grouped[role["id"]]}
                  for role in roles if grouped.get(role["id"])]
        if offline: result.append({"id": "offline", "name": "Offline", "color": self.colors["muted"], "members": offline})
        return result

    @Property(str, notify=changed)
    def selectedName(self): return self._selected["name"] if self._selected else ""

    def _selected_metadata(self):
        if not self._selected: return {}
        values = self.preferences.get("contact_metadata", {})
        return values.get(self._selected["signing_key"], {}) if isinstance(values, dict) else {}

    @Property(str, notify=changed)
    def selectedDisplayName(self):
        remote = self._remote_profiles.get(self.selectedSigningKey, {})
        return str(self._selected_metadata().get("nickname", "")).strip() or str(remote.get("display_name", "")).strip() or self.selectedName

    @Property(str, notify=changed)
    def selectedDisplayFont(self): return str(self._remote_profiles.get(self.selectedSigningKey, {}).get("display_font", "Segoe UI"))

    def _selected_profile_value(self, key: str, default: str = "") -> str:
        return str(self._remote_profiles.get(self.selectedSigningKey, {}).get(key, default))

    @Property(str, notify=changed)
    def selectedCustomStatus(self): return self._selected_profile_value("custom_status")
    @Property(str, notify=changed)
    def selectedBio(self): return self._selected_profile_value("bio")
    @Property(str, notify=changed)
    def selectedPronouns(self): return self._selected_profile_value("pronouns")
    @Property(str, notify=changed)
    def selectedStatusEmoji(self): return self._selected_profile_value("status_emoji")
    @Property(str, notify=changed)
    def selectedBannerColor(self): return self._selected_profile_value("banner_color", self.colors["accent"])
    @Property(str, notify=changed)
    def selectedAvatarUrl(self): return self._selected_profile_value("avatar_data")
    @Property(str, notify=changed)
    def selectedProfileBannerUrl(self): return self._selected_profile_value("banner_data")
    @Property(str, notify=changed)
    def selectedProfileBackgroundUrl(self): return self._selected_profile_value("background_data")

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

    @Property(bool, notify=changed)
    def selectedTyping(self): return bool(self._selected and self._selected["signing_key"] in self._typing_contacts)

    @Property(str, notify=changed)
    def selectedPresence(self):
        if self.selectedIsDemo: return "Online"
        return self._presence_contacts.get(self.selectedSigningKey, "Offline")

    @Property('QVariantList', notify=changed)
    def pendingAttachments(self):
        return [{"name": item["name"], "sizeLabel": self._size_label(item["size"])} for item in self._pending_attachments]

    @staticmethod
    def _size_label(size: int) -> str:
        if size >= 1024 * 1024: return f"{size / (1024 * 1024):.1f} MB"
        if size >= 1024: return f"{size / 1024:.1f} KB"
        return f"{size} B"

    def _upload_attachment(self, item: dict[str, Any], recipient: str) -> dict[str, Any]:
        path = Path(item["path"])
        transfer_id, token = item["transfer_id"], item["token"]
        key = base64.urlsafe_b64decode(item["key"].encode("ascii"))
        chunks = (item["size"] + ATTACHMENT_CHUNK_SIZE - 1) // ATTACHMENT_CHUNK_SIZE
        self.relay.begin_attachment(transfer_id, token, recipient, item["size"], chunks)
        received = self.relay.attachment_status(transfer_id, token)
        digest = hashlib.sha256(); box = secret.SecretBox(key)
        with path.open("rb") as source:
            for index in range(chunks):
                raw = source.read(ATTACHMENT_CHUNK_SIZE)
                if not raw: raise OSError(f"{path.name} changed while it was being sent")
                digest.update(raw)
                if index not in received:
                    encrypted = bytes(box.encrypt(raw))
                    self.relay.upload_attachment_chunk(transfer_id, token, index,
                                                        base64.urlsafe_b64encode(encrypted).decode("ascii"))
                self.transferProgress.emit(f"Uploading {item['name']} — {index + 1} / {chunks} MB")
            if source.read(1): raise OSError(f"{path.name} changed while it was being sent")
        return {"name": item["name"], "mime": item["mime"], "size": item["size"],
                "transfer_id": transfer_id, "token": token, "key": item["key"],
                "chunks": chunks, "sha256": digest.hexdigest()}

    def _download_attachment(self, item: dict[str, Any], message_id: str, index: int) -> dict[str, Any]:
        key = base64.urlsafe_b64decode(str(item["key"]).encode("ascii")); box = secret.SecretBox(key)
        safe_name = "".join(char if char.isalnum() or char in "._- " else "_" for char in str(item["name"]))[:180] or "file"
        destination = self.store.root / f"incoming-{message_id}-{index}-{safe_name}.part"
        digest = hashlib.sha256(); size = 0
        try:
            with destination.open("wb") as output:
                for chunk_index in range(int(item["chunks"])):
                    encoded = self.relay.download_attachment_chunk(str(item["transfer_id"]), str(item["token"]), chunk_index)
                    encrypted = base64.urlsafe_b64decode(encoded.encode("ascii"))
                    raw = box.decrypt(encrypted); output.write(raw); digest.update(raw); size += len(raw)
                    self.transferProgress.emit(f"Downloading {item['name']} — {chunk_index + 1} / {item['chunks']} MB")
            if size != int(item["size"]) or digest.hexdigest() != item["sha256"]:
                raise CryptoError("Attachment failed its encrypted integrity check")
            self.relay.complete_attachment(str(item["transfer_id"]), str(item["token"]))
            return {"name": item["name"], "mime": item["mime"], "size": size, "path": str(destination)}
        except Exception:
            destination.unlink(missing_ok=True)
            raise

    def _store_received_message(self, message: dict[str, Any], sender: dict[str, str]) -> None:
        text = str(message.get("text", ""))
        if text.startswith(SERVER_MESSAGE_PREFIX):
            try:
                payload = json.loads(text.removeprefix(SERVER_MESSAGE_PREFIX))
                server_id, channel_id = str(payload["server_id"]), str(payload["channel_id"])
                if any(server["id"] == server_id and any(channel["id"] == channel_id for channel in server.get("channels", [])) for server in self._servers):
                    self.store.add_server_message(message["id"], server_id, channel_id, sender["signing_key"], "in", message["sent_at"], str(payload["text"])[:4000])
            except (KeyError, TypeError, ValueError, json.JSONDecodeError): pass
            self._notify(); return
        if text.startswith(SERVER_INVITE_PREFIX):
            try:
                invite = json.loads(text.removeprefix(SERVER_INVITE_PREFIX))
                if re.fullmatch(r"[0-9a-f]{32}", str(invite.get("server_id", ""))) and re.fullmatch(r"[A-Za-z0-9_-]{4,32}", str(invite.get("code", ""))):
                    values = list(self.preferences.get("received_server_invites", []))
                    values = [item for item in values if not (item.get("server_id") == invite["server_id"] and item.get("code") == invite["code"])]
                    values.append({"server_id": invite["server_id"], "code": invite["code"], "server_name": str(invite.get("server_name", "Server"))[:48], "from": sender["name"], "expires": int(invite.get("expires", 0))})
                    self.preferences["received_server_invites"] = values[-30:]; self.store.save_preferences(self.preferences)
                    self._status = f"@{sender['name']} invited you to {invite.get('server_name', 'a server')}."
            except (TypeError, ValueError, json.JSONDecodeError): pass
            self._notify(); return
        if text.startswith(PROFILE_SIGNAL_PREFIX):
            try:
                profile = json.loads(text.removeprefix(PROFILE_SIGNAL_PREFIX))
                font = str(profile.get("display_font", "Segoe UI"))
                name = str(profile.get("display_name", "")).strip()[:32]
                if font in DISPLAY_FONTS and name:
                    cleaned = {"display_name": name, "display_font": font,
                               "custom_status": str(profile.get("custom_status", "")).strip()[:80],
                               "bio": str(profile.get("bio", "")).strip()[:190],
                               "pronouns": str(profile.get("pronouns", "")).strip()[:40],
                               "status_emoji": str(profile.get("status_emoji", "")).strip()[:8],
                               "banner_color": str(profile.get("banner_color", ""))[:16]}
                    for key in ("avatar_data", "banner_data", "background_data"):
                        value = str(profile.get(key, ""))
                        if value.startswith("data:image/") and len(value) <= 400_000: cleaned[key] = value
                    self._remote_profiles[sender["signing_key"]] = cleaned
                    self.preferences["remote_profiles"] = self._remote_profiles
                    self.store.save_preferences(self.preferences)
            except (TypeError, ValueError, json.JSONDecodeError): pass
            self._notify(); return
        if self.store.message(str(message.get("id", ""))): return
        attachments = message.get("attachments", [])
        self.store.add_message(message["id"], sender["signing_key"], "in", message["sent_at"], message["text"], attachments)
        is_open = bool(self._selected and self._selected["signing_key"] == sender["signing_key"] and self._page == "chat" and self.application.activeWindow())
        if not is_open:
            key = sender["signing_key"]
            self._unread_counts[key] = self._unread_counts.get(key, 0) + 1
            self.preferences["unread_counts"] = self._unread_counts
            self.store.save_preferences(self.preferences)
        if bool(self.preferences.get("message_sounds", True)) and self.presence != "Do Not Disturb":
            self.application.beep()
        if not any("transfer_id" in item for item in attachments):
            self._notify(); return
        def work():
            return [self._download_attachment(item, message["id"], index) if "transfer_id" in item else item
                    for index, item in enumerate(attachments)]
        def complete(files, error):
            if error: self._status = f"Attachment download failed: {error}"; self._notify(); return
            try:
                self.store.replace_attachments(message["id"], files)
            finally:
                for item in files:
                    path = Path(str(item.get("path", "")))
                    if path.suffix == ".part": path.unlink(missing_ok=True)
            self._notify()
        self.run_job(work, complete)

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
            attachments = json.loads(row["attachments"] or "[]") if show_content else []
            for attachment in attachments:
                path = Path(str(attachment.get("path", "")))
                attachment["sizeLabel"] = self._size_label(int(attachment.get("size", 0)))
                attachment["previewUrl"] = QUrl.fromLocalFile(str(path)).toString() if str(attachment.get("mime", "")).startswith("image/") and path.is_file() else ""
                attachment["available"] = path.is_file()
            result.append({
                "id": row["id"],
                "sender": "YOU" if row["direction"] == "out" else self.selectedDisplayName,
                "plainText": row["plaintext"] if show_content else "", "body": markdown_html(row["plaintext"]) if show_content else "<i>Message content hidden by Privacy settings.</i>",
                "timestamp": stamp.strftime("%H:%M" if use_24_hour else "%I:%M %p").lstrip("0"),
                "fullTimestamp": stamp.strftime("%d %B %Y at %H:%M" if use_24_hour else "%d %B %Y at %I:%M %p"),
                "showDate": date_key != previous_date,
                "dateLabel": stamp.strftime("%A, %d %B %Y"),
                "outgoing": row["direction"] == "out",
                "senderFont": self.displayFont if row["direction"] == "out" else self.selectedDisplayFont,
                "attachments": attachments,
                "searchText": (row["plaintext"] + " " + " ".join(str(item.get("name", "")) for item in attachments)).lower(),
            })
            previous_date = date_key
        return result

    @Property(str, notify=changed)
    def displayName(self): return str(self.preferences.get("display_name", self.username))

    @Property(str, notify=changed)
    def displayFont(self):
        value = str(self.preferences.get("display_font", "Segoe UI"))
        return value if value in DISPLAY_FONTS else "Segoe UI"

    @Property('QVariantList', constant=True)
    def displayFontOptions(self): return list(DISPLAY_FONT_OPTIONS)

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

    def _media_url(self, key: str) -> str:
        path = Path(str(self.preferences.get(key, "")))
        return QUrl.fromLocalFile(str(path)).toString() if path.is_file() else ""

    @Property(str, notify=changed)
    def wallpaperUrl(self): return self._media_url("wallpaper")

    @Property(str, notify=changed)
    def profileBackgroundUrl(self): return self._media_url("profile_background")

    @Property(str, notify=changed)
    def profileBannerUrl(self): return self._media_url("profile_banner")

    @Property(float, notify=changed)
    def wallpaperOpacity(self): return max(0., min(1., float(self.preferences.get("wallpaper_opacity", .7))))

    @Property(float, notify=changed)
    def panelOpacity(self): return max(.2, min(1., float(self.preferences.get("panel_opacity", .94))))

    @Property(float, notify=changed)
    def controlOpacity(self): return max(.2, min(1., float(self.preferences.get("control_opacity", 1.))))

    @Property(float, notify=changed)
    def messageBackgroundOpacity(self): return max(.0, min(1., float(self.preferences.get("message_background_opacity", 1.))))

    @Property(str, notify=changed)
    def buttonColor(self): return str(self.preferences.get("button_color", self.colors["tile"]))

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
            identity = unlock_identity(self.vault or {}, passphrase)
        except CryptoError as exc:
            self._status = str(exc); self._notify()

        else:
            self.identity = identity
            self.relay = RelayClient(self.relay_url)
            self._status = "Connecting your account to the hosted relay..."; self._busy = True; self._notify()
            def complete(_result, error):
                self._busy = False
                if error:
                    self.identity = None; self._status = str(error); self._notify(); return
                if self._migrate_relay:
                    self.vault = dict(self.vault or {}); self.vault["relay"] = self.relay_url
                    self.store.save_vault(self.vault); self._migrate_relay = False
                self._enter_messenger()
            self.run_job(lambda: self.relay.register(public_card(identity, str((self.vault or {})["name"]))), complete)

    @Slot(str, str)
    def signup(self, username: str, passphrase: str):
        name = username.strip().lower()
        if not re.fullmatch(r"[a-zA-Z0-9_]{1,32}", name):
            self._status = "Use 1-32 letters, numbers, or underscores."; self._notify(); return
        try:
            identity = Identity.generate(); locked = lock_identity(identity, passphrase)
        except CryptoError as exc:
            self._status = str(exc); self._notify(); return
        chosen_relay = DEFAULT_RELAY_URL
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
        self._remote_profiles[DEMO_CARD["signing_key"]] = dict(DEMO_PROFILE)
        self._page = "chat"; self._status = ""; self._relay_status = "Connecting..."
        self.poll_timer.start(); self.presence_timer.start(); self.poll_inbox(); self._publish_presence(); self.refreshServers(); self._notify()

    @Slot(str)
    def openPage(self, page: str): self._page = page; self._notify()

    @Slot()
    def refreshServers(self):
        if not self.identity: return
        self.run_job(lambda: self.relay.servers(self.identity.signing_public),
                     lambda result, error: self._finish_servers(result, error))

    def _finish_servers(self, result, error):
        if error: self._status = f"Could not refresh servers: {error}"; self._notify(); return
        self._servers = list(result or [])
        if self._selected_server_id and not any(server["id"] == self._selected_server_id for server in self._servers): self._selected_server_id = ""
        if self._selected_server_id:
            channels = self.selectedServer.get("channels", [])
            if not any(channel["id"] == self._selected_channel_id for channel in channels):
                self._selected_channel_id = next((channel["id"] for channel in channels if channel.get("type") == "text"), "")
        self._notify()

    def _server_action(self, action: str, server_id: str, payload: dict[str, Any], success: str):
        if not self.identity: return
        signed = sign_server_action(self.identity, action, server_id, payload)
        def complete(result, error):
            if error: self._status = str(error)
            else:
                server = dict(result); self._servers = [item for item in self._servers if item["id"] != server["id"]] + [server]
                self._selected_server_id = server["id"]; self._page = "server"; self._status = success
            self._notify()
        self.run_job(lambda: self.relay.server_action(signed), complete)

    @Slot(str)
    def createServer(self, name: str):
        if not self.identity: return
        self._server_action("server.create", new_server_id(), {"name": name, "owner_card": public_card(self.identity, self.username), "accent": self.colors["accent"]}, "Server created.")

    @Slot(str, str)
    def joinServer(self, server_id: str, code: str):
        if not self.identity: return
        self._server_action("invite.redeem", server_id.strip(), {"code": code.strip(), "member_card": public_card(self.identity, self.username)}, "Server joined.")

    @Slot(str, str)
    def acceptServerInvite(self, server_id: str, code: str):
        values = [item for item in self.preferences.get("received_server_invites", []) if not (item.get("server_id") == server_id and item.get("code") == code)]
        self.preferences["received_server_invites"] = values; self.store.save_preferences(self.preferences)
        self.joinServer(server_id, code)

    @Slot(str)
    def selectServer(self, server_id: str):
        self._selected_server_id = server_id; self._page = "server"
        self._selected_channel_id = next((channel["id"] for channel in self.selectedServer.get("channels", []) if channel.get("type") == "text"), "")
        self._notify()

    @Slot(str)
    def selectServerChannel(self, channel_id: str): self._selected_channel_id = channel_id; self._notify()

    @Slot(str)
    def sendServerMessage(self, text: str):
        text = text.strip()
        if not self.identity or not self._selected_server_id or not self._selected_channel_id or not text or self._sending: return
        if len(text) > 4000: self._status = "Messages are limited to 4,000 characters."; self._notify(); return
        server, identity, channel_id = dict(self.selectedServer), self.identity, self._selected_channel_id
        body = SERVER_MESSAGE_PREFIX + json.dumps({"server_id": self._selected_server_id, "channel_id": channel_id, "text": text}, separators=(",", ":"))
        recipients = [member["card"] for member in server.get("members", []) if member["signing_key"] != identity.signing_public]
        local_id, sent_at = uuid.uuid4().hex, int(time.time())
        self._sending = True; self._status = "Sending encrypted channel message..."; self._notify()
        def work():
            packets = [encrypt_message(identity, recipient, body) for recipient in recipients]
            signed = sign_server_action(identity, "message.send", server["id"], {"channel_id": channel_id, "packets": packets})
            self.relay.send_server_message(signed)
        def complete(_result, error):
            self._sending = False
            if error: self._status = f"Not sent: {error}"
            else:
                self.store.add_server_message(local_id, server["id"], channel_id, identity.signing_public, "out", sent_at, text)
                self._status = "Delivered to encrypted server channel."
            self._notify()
        self.run_job(work, complete)

    @Slot(str)
    def createServerChannel(self, name: str):
        if self._selected_server_id: self._server_action("channel.create", self._selected_server_id, {"name": name, "type": "text"}, "Channel created.")

    @Slot(str)
    def createServerCategory(self, name: str):
        # Voice rows with a reserved topic remain compatible with relays deployed
        # before native category rows were introduced.
        if self._selected_server_id: self._server_action("channel.create", self._selected_server_id, {"name": name, "type": "voice", "topic": "category"}, "Category created.")

    @Slot(str)
    def toggleServerCategory(self, category_id: str):
        key = f"{self._selected_server_id}:{category_id}"
        self._collapsed_server_categories[key] = not self._collapsed_server_categories.get(key, False)
        self._save_preferences(collapsed_server_categories=self._collapsed_server_categories)
        self._notify()

    @Slot(str, str)
    def moveServerChannel(self, channel_id: str, category_id: str):
        channel = next((item for item in self.selectedServer.get("channels", []) if item.get("id") == channel_id and item.get("type") == "text"), None)
        if channel and self._selected_server_id:
            self._server_action("channel.update", self._selected_server_id,
                                {"channel_id": channel_id, "name": channel["name"], "category_id": category_id,
                                 "topic": f"category:{category_id}" if category_id else ""},
                                "Channel moved.")

    @Slot()
    def createServerInvite(self):
        self.createServerInviteWithOptions(self.newInviteCode(), "Forever", [])

    @Slot(result=str)
    def newInviteCode(self): return uuid.uuid4().hex[:16]

    @Slot(str, str, 'QVariantList')
    def createServerInviteWithOptions(self, requested_code: str, expiry: str, recipients):
        if not self.identity or not self._selected_server_id: return
        code = requested_code.strip() or self.newInviteCode()
        seconds = {"1 day": 86400, "7 days": 7 * 86400, "Forever": 0}.get(expiry, 86400)
        expires = 0 if seconds == 0 else int(time.time()) + seconds
        server, identity = dict(self.selectedServer), self.identity
        signed = sign_server_action(identity, "invite.create", server["id"], {"code": code, "role_id": "member", "uses": -1, "expires": expires})
        selected = set(map(str, recipients)); contacts = [card for card in self.store.contacts() if card["signing_key"] in selected and card["signing_key"] != DEMO_CARD["signing_key"]]
        def work():
            updated = self.relay.server_action(signed)
            signal = SERVER_INVITE_PREFIX + json.dumps({"server_id": server["id"], "server_name": server["name"], "code": code, "expires": expires}, separators=(",", ":"))
            for contact in contacts: self.relay.send(encrypt_message(identity, contact, signal))
            return updated
        def complete(result, error):
            if error: self._status = f"Invite was not created: {error}"
            else:
                updated = dict(result); self._servers = [item for item in self._servers if item["id"] != updated["id"]] + [updated]
                self._status = f"Invite code: {code}" + (f" — sent to {len(contacts)} contact{'s' if len(contacts) != 1 else ''}." if contacts else ".")
            self._notify()
        self.run_job(work, complete)

    @Slot(str, str)
    def updateServer(self, name: str, accent: str):
        if self._selected_server_id: self._server_action("server.update", self._selected_server_id, {"name": name, "accent": accent, "icon": self.selectedServer.get("icon", "")}, "Server settings saved.")

    @Slot()
    def chooseServerIcon(self):
        self.chooseServerIconFor(self._selected_server_id)

    @Slot(str)
    def chooseServerIconFor(self, server_id: str):
        server = next((item for item in self._servers if item["id"] == server_id), None)
        if not server: return
        filename, _ = QFileDialog.getOpenFileName(None, "Choose server icon", "", "Images (*.png *.jpg *.jpeg *.webp)")
        if not filename: return
        icon = _profile_image_data(Path(filename))
        if not icon: self._status = "Could not read that server icon."; self._notify(); return
        self._server_action("server.update", server["id"], {"name": server["name"], "accent": server.get("accent", self.colors["accent"]), "icon": icon}, "Server icon saved.")

    @Slot(str)
    def removeServerIcon(self, server_id: str):
        server = next((item for item in self._servers if item["id"] == server_id), None)
        if server: self._server_action("server.update", server["id"], {"name": server["name"], "accent": server.get("accent", self.colors["accent"]), "icon": ""}, "Server icon removed.")

    @Slot(str)
    def chooseServerFolderIcon(self, folder_id: str):
        filename, _ = QFileDialog.getOpenFileName(None, "Choose folder icon", "", "Images (*.png *.jpg *.jpeg *.webp)")
        if not filename: return
        icon = _profile_image_data(Path(filename))
        if not icon: self._status = "Could not read that folder icon."; self._notify(); return
        layout = self.preferences.get("server_layout", [])
        for item in layout:
            if isinstance(item, dict) and item.get("type") == "folder" and item.get("id") == folder_id: item["icon"] = icon
        self._save_preferences(server_layout=layout)

    @Slot(str)
    def removeServerFolderIcon(self, folder_id: str):
        layout = self.preferences.get("server_layout", [])
        for item in layout:
            if isinstance(item, dict) and item.get("type") == "folder" and item.get("id") == folder_id: item["icon"] = ""
        self._save_preferences(server_layout=layout)

    @Slot()
    def deleteServer(self):
        if not self.identity or not self._selected_server_id: return
        server_id = self._selected_server_id
        signed = sign_server_action(self.identity, "server.delete", server_id, {})
        def complete(_result, error):
            if error: self._status = f"Server was not deleted: {error}"
            else:
                self._servers = [server for server in self._servers if server["id"] != server_id]
                self._selected_server_id = ""; self._selected_channel_id = ""; self._page = "chat"
                layout = []
                for item in self.preferences.get("server_layout", []):
                    if not isinstance(item, dict): continue
                    if item.get("type") == "folder":
                        item = {**item, "servers": [value for value in item.get("servers", []) if value != server_id]}
                        if item["servers"]: layout.append(item)
                    elif item.get("id") != server_id: layout.append(item)
                self.preferences["server_layout"] = layout; self.store.save_preferences(self.preferences)
                self._status = "Server deleted."
            self._notify()
        self.run_job(lambda: self.relay.server_action(signed), complete)

    @Slot(str, str, 'QVariantList')
    def createServerRole(self, name: str, color: str, permissions):
        if self._selected_server_id: self._server_action("role.create", self._selected_server_id, {"name": name, "color": color, "permissions": list(permissions)}, "Role created.")

    @Slot(str, str)
    def renameServerRole(self, role_id: str, name: str):
        role = next((item for item in self.selectedServer.get("roles", []) if item["id"] == role_id), None)
        if role and name.strip(): self._server_action("role.update", self._selected_server_id, {"role_id": role_id, "name": name.strip(), "color": role.get("color", "#94a3b8"), "permissions": role.get("permissions", [])}, "Role renamed.")

    @Slot(str, 'QVariantList')
    def setServerMemberRoles(self, member: str, roles):
        if self._selected_server_id: self._server_action("member.roles", self._selected_server_id, {"member": member, "roles": list(roles)}, "Member roles updated.")

    @Slot(str, str)
    def moveServer(self, source_id: str, target_id: str):
        if source_id == target_id: return
        layout = [dict(item) for item in self.preferences.get("server_layout", []) if isinstance(item, dict)]
        placed = {item.get("id") for item in layout if item.get("type") == "server"} | {value for item in layout if item.get("type") == "folder" for value in item.get("servers", [])}
        layout.extend({"type": "server", "id": server["id"]} for server in self._servers if server["id"] not in placed)
        layout = [{**item, "servers": [value for value in item.get("servers", []) if value != source_id]} if item.get("type") == "folder" else item for item in layout if not (item.get("type") == "server" and item.get("id") == source_id)]
        target_index = next((index for index, item in enumerate(layout) if item.get("id") == target_id or target_id in item.get("servers", [])), len(layout))
        target = layout[target_index] if target_index < len(layout) else None
        if target and target.get("type") == "folder": target["servers"].append(source_id)
        elif target:
            layout[target_index] = {"type": "folder", "id": uuid.uuid4().hex, "name": "Server folder", "color": self.colors["accent"], "servers": [target_id, source_id]}
        else: layout.append({"type": "server", "id": source_id})
        self._save_preferences(server_layout=[item for item in layout if item.get("type") != "folder" or item.get("servers")])

    @Slot(str, str, bool)
    def reorderServer(self, source_id: str, target_id: str, before: bool):
        if source_id == target_id: return
        layout = [dict(item) for item in self.preferences.get("server_layout", []) if isinstance(item, dict)]
        placed = {item.get("id") for item in layout if item.get("type") == "server"} | {value for item in layout if item.get("type") == "folder" for value in item.get("servers", [])}
        layout.extend({"type": "server", "id": server["id"]} for server in self._servers if server["id"] not in placed)
        for item in layout:
            if item.get("type") == "folder": item["servers"] = [value for value in item.get("servers", []) if value != source_id]
        layout = [item for item in layout if not (item.get("type") == "server" and item.get("id") == source_id)]
        inserted = False
        for index, item in enumerate(layout):
            if item.get("type") == "folder" and target_id in item.get("servers", []):
                target_index = item["servers"].index(target_id) + (0 if before else 1)
                item["servers"].insert(target_index, source_id); inserted = True; break
            if item.get("type") == "server" and item.get("id") == target_id:
                layout.insert(index + (0 if before else 1), {"type": "server", "id": source_id}); inserted = True; break
        if not inserted: layout.append({"type": "server", "id": source_id})
        self._save_preferences(server_layout=[item for item in layout if item.get("type") != "folder" or item.get("servers")])

    @Slot(str)
    def moveServerOutOfFolder(self, source_id: str):
        layout = [dict(item) for item in self.preferences.get("server_layout", []) if isinstance(item, dict)]
        found = False
        for item in layout:
            if item.get("type") == "folder" and source_id in item.get("servers", []):
                item["servers"] = [value for value in item["servers"] if value != source_id]; found = True
        if found:
            layout = [item for item in layout if item.get("type") != "folder" or item.get("servers")]
            layout.append({"type": "server", "id": source_id})
            self._save_preferences(server_layout=layout)

    @Slot(str, str, str)
    def customizeServerFolder(self, folder_id: str, name: str, color: str):
        layout = self.preferences.get("server_layout", [])
        for item in layout:
            if isinstance(item, dict) and item.get("type") == "folder" and item.get("id") == folder_id:
                item["name"], item["color"] = name.strip()[:32] or "Server folder", color[:16]
        self._save_preferences(server_layout=layout)

    @Slot(str)
    def toggleServerFolder(self, folder_id: str):
        expanded = list(self.preferences.get("expanded_server_folders", []))
        if folder_id in expanded: expanded.remove(folder_id)
        else: expanded.append(folder_id)
        self._save_preferences(expanded_server_folders=expanded)


    @Slot(str)
    def openSettingsTab(self, tab: str): self._settings_tab = tab; self._page = "settings"; self._notify()

    @Slot()
    def toggleSidebar(self):
        self._sidebar_expanded = not self._sidebar_expanded
        if bool(self.preferences.get("remember_sidebar", True)):
            self._save_preferences(sidebar_expanded=self._sidebar_expanded)
        else:
            self._notify()

    @Slot(int)
    def setSidebarWidth(self, value: int):
        width = max(230, min(420, int(value)))
        if width == self._sidebar_width: return
        self._sidebar_width = width
        self._save_preferences(sidebar_width=width)

    @Slot(int)
    def setServerChannelWidth(self, value: int):
        width = max(150, min(360, int(value)))
        if width != self._server_channel_width: self._server_channel_width = width; self._save_preferences(server_channel_width=width)

    @Slot(int)
    def setServerMemberWidth(self, value: int):
        width = max(170, min(360, int(value)))
        if width != self._server_member_width: self._server_member_width = width; self._save_preferences(server_member_width=width)

    @Slot(str)
    def selectContact(self, signing_key: str):
        self.setTyping(False)
        self._selected = next((c for c in self.store.contacts() if c["signing_key"] == signing_key), None)
        if self._unread_counts.pop(signing_key, 0):
            self.preferences["unread_counts"] = self._unread_counts
            self.store.save_preferences(self.preferences)
        self._pending_attachments = []
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
                self._publish_presence(); self._publish_profile()
            except CryptoError as exc: self._status = str(exc)
            self._notify()
        self.run_job(lambda: self.relay.lookup(username), complete)

    @Slot()
    def chooseAttachments(self):
        if self._sending: return
        filenames, _ = QFileDialog.getOpenFileNames(None, "Attach files", "", "All files (*)")
        if not filenames: return
        pending = list(self._pending_attachments)
        try:
            for filename in filenames:
                path = Path(filename)
                size = path.stat().st_size
                if not path.is_file() or size <= 0: raise ValueError(f"{path.name} is empty or unavailable")
                if len(pending) >= 5: raise ValueError("A message can contain up to 5 files")
                if any(item["path"] == str(path) for item in pending): continue
                pending.append({"path": str(path), "name": path.name,
                                "mime": mimetypes.guess_type(path.name)[0] or "application/octet-stream", "size": size})
            if sum(item["size"] for item in pending) > 50 * 1024 * 1024:
                raise ValueError("Attachments are limited to 50 MB per message")
            self._pending_attachments = pending
            self._status = ""
        except (OSError, ValueError) as exc:
            self._status = f"Could not attach files: {exc}"
        self._notify()

    @Slot(int)
    def removeAttachment(self, index: int):
        if not self._sending and 0 <= index < len(self._pending_attachments):
            self._pending_attachments.pop(index); self._notify()

    @Slot(str, int)
    def saveAttachment(self, message_id: str, index: int):
        row = self.store.message(message_id)
        if not row: return
        try:
            attachments = json.loads(row["attachments"] or "[]")
            attachment = attachments[index]
            if attachment.get("transfer_id"):
                self._status = f"Downloading {attachment['name']}..."; self._notify()
                def work(): return self._download_attachment(attachment, message_id, index)
                def complete(file, error):
                    if error: self._status = f"Attachment download failed: {error}"; self._notify(); return
                    attachments[index] = file
                    try: self.store.replace_attachments(message_id, attachments)
                    finally: Path(str(file["path"])).unlink(missing_ok=True)
                    self._status = f"Downloaded {file['name']}. Choose Save to export it."; self._notify()
                self.run_job(work, complete); return
            source = Path(str(attachment["path"]))
            filename, _ = QFileDialog.getSaveFileName(None, "Save attachment", attachment["name"], "All files (*)")
            if filename:
                shutil.copy2(source, filename); self._status = f"Saved {attachment['name']}."
        except (IndexError, KeyError, OSError, TypeError, json.JSONDecodeError) as exc:
            self._status = f"Could not save attachment: {exc}"
        self._notify()

    @Slot(str)
    def sendMessage(self, text: str):
        self.setTyping(False)
        text = text.strip()
        if not self._selected or self._sending or (not text and not self._pending_attachments): return
        if len(text) > 4000:
            self._status = "Messages are limited to 4,000 characters."; self._notify(); return
        contact = self._selected
        identity = self.identity
        for item in self._pending_attachments:
            item.setdefault("transfer_id", str(uuid.uuid4()))
            item.setdefault("token", base64.urlsafe_b64encode(utils.random(32)).decode("ascii"))
            item.setdefault("key", base64.urlsafe_b64encode(utils.random(secret.SecretBox.KEY_SIZE)).decode("ascii"))
        pending = [dict(item) for item in self._pending_attachments]
        self._sending = True; self._status = "Encrypting attachments..." if pending else "Sending encrypted packet..."; self._notify()
        def work():
            if contact["signing_key"] == DEMO_CARD["signing_key"]:
                files = [{"name": item["name"], "mime": item["mime"], "size": item["size"],
                          "data": base64.urlsafe_b64encode(Path(item["path"]).read_bytes()).decode("ascii")} for item in pending]
            else:
                files = [self._upload_attachment(item, contact["encryption_key"]) for item in pending]
            packet = encrypt_message(identity, contact, text, files)  # type: ignore[arg-type]
            if contact["signing_key"] != DEMO_CARD["signing_key"]:
                self.relay.send(packet); return packet, None
            time.sleep(.2)
            received = decrypt_message(DEMO_IDENTITY, packet, public_card(identity, self.username))  # type: ignore[arg-type]
            response = encrypt_message(DEMO_IDENTITY, public_card(identity, self.username), f"Encrypted echo: {received['text']}")  # type: ignore[arg-type]
            return packet, response
        def complete(result, error):
            self._sending = False
            if error: self._status = f"Not sent: {error}"; self._notify(); return
            packet, response = result
            self.store.add_message(packet["id"], contact["signing_key"], "out", int(time.time()), text, pending)
            self._pending_attachments = []
            self._status = "Delivered to encrypted relay."
            if response:
                message = decrypt_message(identity, response, DEMO_CARD)  # type: ignore[arg-type]
                self.store.add_message(message["id"], DEMO_CARD["signing_key"], "in", message["sent_at"], message["text"], message.get("attachments"))
            self._notify()
        self.run_job(work, complete)

    @Slot(str, str, str, str, str, str, str)
    def saveProfile(self, display_name: str, custom_status: str, bio: str, pronouns: str, banner_color: str, status_emoji: str, display_font: str):
        if display_font not in DISPLAY_FONTS: display_font = "Segoe UI"
        self._save_preferences(display_name=display_name.strip()[:32] or self.username,
                               custom_status=custom_status.strip()[:80], bio=bio.strip()[:190],
                               pronouns=pronouns.strip()[:40], banner_color=banner_color, status_emoji=status_emoji.strip()[:8],
                               display_font=display_font)
        self._publish_profile()
        self._status = "Profile saved."; self._notify()

    @Slot(str)
    def setDisplayFont(self, display_font: str):
        if display_font not in DISPLAY_FONTS: return
        self._save_preferences(display_font=display_font)
        self._publish_profile()

    def _publish_profile(self):
        if not self.identity: return
        contacts = [c for c in self.store.contacts() if c["signing_key"] != DEMO_CARD["signing_key"]]
        if not contacts: return
        profile = {"display_name": self.displayName, "display_font": self.displayFont,
                   "custom_status": self.customStatus, "bio": self.bio, "pronouns": self.pronouns,
                   "status_emoji": self.statusEmoji, "banner_color": self.bannerColor}
        for source_key, payload_key in (("avatar", "avatar_data"), ("profile_banner", "banner_data"),
                                        ("profile_background", "background_data")):
            path = Path(str(self.preferences.get(source_key, "")))
            preview = _profile_image_data(path) if path.is_file() else ""
            if preview: profile[payload_key] = preview
        payload = PROFILE_SIGNAL_PREFIX + json.dumps(profile, separators=(",", ":"))
        identity = self.identity
        self.run_job(lambda: [self.relay.send(encrypt_message(identity, contact, payload)) for contact in contacts], lambda _r, _e: None)

    @Slot(str)
    def setPresence(self, value: str):
        if value in PRESENCE_COLORS:
            self._save_preferences(presence=value); self._publish_presence()

    @Slot(str)
    def setTheme(self, value: str):
        if value in THEMES: self._save_preferences(theme=value)

    @Slot()
    def chooseCustomAccent(self):
        color = QColorDialog.getColor(QColor(str(self.preferences.get("custom_accent", "#82d2ff"))), None, "Choose interface accent")
        if color.isValid(): self._save_preferences(theme="Custom", custom_accent=color.name())

    @Slot()
    def chooseCustomBackground(self):
        color = QColorDialog.getColor(QColor(str(self.preferences.get("custom_background", "#101112"))), None, "Choose app background")
        if color.isValid(): self._save_preferences(theme="Custom", custom_background=color.name())

    @Slot()
    def chooseButtonColor(self):
        color = QColorDialog.getColor(QColor(self.buttonColor), None, "Choose button color")
        if color.isValid(): self._save_preferences(button_color=color.name())

    @Slot()
    def resetButtonColor(self):
        self.preferences.pop("button_color", None); self.store.save_preferences(self.preferences); self._notify()

    def _choose_media(self, key: str, name: str, title: str):
        filename, _ = QFileDialog.getOpenFileName(None, title, "", "Images (*.png *.jpg *.jpeg *.webp *.gif)")
        if not filename: return
        try: self._save_preferences(**{key: str(self.store.save_media(Path(filename), name))})
        except (OSError, ValueError) as exc: self._status = f"Could not use that image: {exc}"; self._notify()

    @Slot()
    def chooseWallpaper(self): self._choose_media("wallpaper", "wallpaper", "Choose app wallpaper")

    @Slot()
    def chooseProfileBackground(self): self._choose_media("profile_background", "profile-background", "Choose full profile background")

    @Slot()
    def chooseProfileBanner(self): self._choose_media("profile_banner", "profile-banner", "Choose profile banner")

    @Slot(str)
    def clearMedia(self, key: str):
        if key not in {"wallpaper", "profile_background", "profile_banner"}: return
        path = Path(str(self.preferences.pop(key, "")))
        self.store.save_preferences(self.preferences); self._notify()
        def remove_file(attempt: int = 0):
            try:
                if path.is_file() and path.parent == self.store.root: path.unlink(missing_ok=True)
            except PermissionError:
                if attempt < 10: QTimer.singleShot(200, lambda: remove_file(attempt + 1))
        QTimer.singleShot(0, remove_file)

    @Slot(str, float)
    def setOpacity(self, key: str, value: float):
        if key in {"wallpaper_opacity", "panel_opacity", "control_opacity", "message_background_opacity"}:
            minimum = .0 if key == "wallpaper_opacity" else .2
            self._save_preferences(**{key: max(minimum, min(1., value))})

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
                "User-Agent": f"Nightseal/{__version__}",
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
            executable = Path(sys.executable).resolve()
            installed = bool(getattr(sys, "frozen", False) and (executable.parent / "unins000.exe").is_file())
            asset_name = _release_asset_name(version, installed)
            asset = next((item for item in release.get("assets", []) if item.get("name") == asset_name), None)
            if not asset: raise ValueError(f"Release v{version} has no {asset_name} asset")
            digest = str(asset.get("digest", ""))
            if not digest.startswith("sha256:"):
                raise ValueError("Release asset has no GitHub SHA-256 digest")
            updates = self.store.root / "updates"; updates.mkdir(parents=True, exist_ok=True)
            partial = updates / f"{asset_name}.part"
            download = urllib.request.Request(str(asset["browser_download_url"]), headers={"User-Agent": f"Nightseal/{__version__}"})
            hasher = hashlib.sha256(); size = 0
            with urllib.request.urlopen(download, timeout=30) as response, partial.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    size += len(chunk)
                    if size > 300_000_000: raise ValueError("Release download exceeds the size limit")
                    hasher.update(chunk); output.write(chunk)
            if hasher.hexdigest().lower() != digest.split(":", 1)[1].lower():
                partial.unlink(missing_ok=True); raise ValueError("Downloaded update failed SHA-256 verification")
            stage = updates / asset_name
            os.replace(partial, stage)
            mode = "installer" if installed else ("portable" if getattr(sys, "frozen", False) else "portable_launch")
            return {"state": "ready", "version": version, "stage": str(stage), "mode": mode}
        def complete(result, error):
            self._checking_updates = False
            if error: self._update_status = f"Update check failed: {error}"
            elif result["state"] == "none": self._update_status = "No published releases are available yet."
            elif result["state"] == "current": self._update_status = f"Nightseal {__version__} is up to date."
            else:
                self._update_version, self._update_stage, self._update_mode = result["version"], result["stage"], result["mode"]
                self._update_status = f"Version {self._update_version} is downloaded and ready."
            self._notify()
        self.run_job(work, complete)

    @Slot()
    def restartToUpdate(self):
        if not self._update_stage: return
        stage = Path(self._update_stage).resolve()
        updates = stage.parent
        script = updates / f"apply-v{self._update_version}.ps1"
        target = Path(sys.executable).resolve() if self._update_mode in {"installer", "portable"} else self.store.root / stage.name
        content = _update_apply_script(self._update_mode)
        log = updates / f"apply-v{self._update_version}.log"
        log.unlink(missing_ok=True)
        arguments = [str(os.getpid()), str(stage), str(target), str(log)]
        script.write_text(content, encoding="utf-8")
        command = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
                   "-File", str(script), *arguments]
        try:
            helper = _spawn_update_helper(command, updates)
        except OSError as exc:
            self._update_status = f"Could not start the updater: {exc}"; self._notify(); return
        self._update_status = "Restarting to finish the update..."; self._notify()
        def finish_handoff():
            code = helper.poll()
            if code is None:
                self.application.quit(); return
            detail = log.read_text("utf-8", errors="replace").strip() if log.is_file() else f"helper exited with code {code}"
            self._update_status = f"Updater could not start: {detail}"; self._notify()
        QTimer.singleShot(750, finish_handoff)

    @Slot(str, bool)
    def setPreference(self, key: str, value: bool):
        if key == "typing_indicators" and not value: self.setTyping(False)
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

    @Slot(bool)
    def setTyping(self, active: bool):
        enabled = bool(self.preferences.get("typing_indicators", True))
        active = bool(active and enabled and self.identity and self._selected and not self.selectedIsDemo)
        if active == self._typing_active: return
        self._typing_active = active
        if active: self.typing_timer.start()
        else: self.typing_timer.stop()
        self._send_typing_signal(active)

    def _refresh_typing(self):
        if self._typing_active: self._send_typing_signal(True)

    def _send_typing_signal(self, active: bool):
        if not self.identity or not self._selected or self.selectedIsDemo: return
        packet = encrypt_message(self.identity, self._selected, TYPING_SIGNAL_PREFIX + ("on" if active else "off"))
        self.run_job(lambda: self.relay.send_typing(packet), lambda _result, _error: None)

    def _publish_presence(self):
        if not self.identity or self._closing: return
        status = "Offline" if self.presence == "Invisible" else self.presence
        cards = self.store.contacts() + [member.get("card", {}) for server in self._servers for member in server.get("members", [])]
        contacts = list({card["signing_key"]: card for card in cards if card.get("signing_key") not in {DEMO_CARD["signing_key"], self.identity.signing_public}}.values())
        if not contacts: return
        identity = self.identity
        def work():
            for contact in contacts:
                self.relay.send_presence(encrypt_message(identity, contact, PRESENCE_SIGNAL_PREFIX + status))
        self.run_job(work, lambda _result, _error: None)

    def poll_inbox(self):
        if not self.identity or self._closing or self._polling: return
        if not self.application.activeWindow(): interval = 5000
        elif self._selected: interval = 500
        else: interval = 2500
        self.poll_timer.setInterval(interval)
        self._polling = True
        identity = self.identity
        def complete(state, error):
            self._polling = False
            if self._closing: return
            if error: self._relay_status = "Relay offline"
            else:
                self._relay_status = "Relay connected"
                for envelope in state.get("messages", []):
                    sender = self.store.contact_by_encryption_key(str(envelope.get("from", "")))
                    if not sender:
                        sender = next((member.get("card") for server in self._servers for member in server.get("members", []) if member.get("card", {}).get("encryption_key") == str(envelope.get("from", ""))), None)
                    if not sender: continue
                    try:
                        message = decrypt_message(identity, envelope, sender)
                        self._store_received_message(message, sender)
                    except CryptoError: pass
                typing_contacts: set[str] = set()
                for envelope in state.get("typing", []):
                    sender = self.store.contact_by_encryption_key(str(envelope.get("from", "")))
                    if not sender: continue
                    try:
                        signal = decrypt_message(identity, envelope, sender).get("text", "")
                        if signal == TYPING_SIGNAL_PREFIX + "on": typing_contacts.add(sender["signing_key"])
                    except CryptoError: pass
                self._typing_contacts = typing_contacts
                presence_contacts: dict[str, str] = {}
                for envelope in state.get("presence", []):
                    sender = self.store.contact_by_encryption_key(str(envelope.get("from", "")))
                    if not sender:
                        sender = next((member.get("card") for server in self._servers for member in server.get("members", []) if member.get("card", {}).get("encryption_key") == str(envelope.get("from", ""))), None)
                    if not sender: continue
                    try:
                        signal = str(decrypt_message(identity, envelope, sender).get("text", ""))
                        status = signal.removeprefix(PRESENCE_SIGNAL_PREFIX) if signal.startswith(PRESENCE_SIGNAL_PREFIX) else ""
                        if status in {"Online", "Away", "Do Not Disturb"}: presence_contacts[sender["signing_key"]] = status
                    except CryptoError: pass
                self._presence_contacts = presence_contacts
            self._notify()
        self.run_job(lambda: self.relay.inbox_state(identity.encryption_public), complete)

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
        self.setTyping(False)
        self._closing = True; self.poll_timer.stop(); self.typing_timer.stop(); self.presence_timer.stop()
        try: self.store.db.close()
        except sqlite3.Error: pass
        if self.local_relay:
            relay = self.local_relay
            def stop():
                try: relay.shutdown(); relay.server_close(); relay.RequestHandlerClass.db.connection.close()
                except (OSError, sqlite3.Error): pass
            threading.Thread(target=stop, name="secure-tiles-relay-shutdown", daemon=True).start()


def main():
    smoke_test = "--smoke-test" in sys.argv or os.environ.get("NIGHTSEAL_SMOKE_TEST") == "1"
    if smoke_test: sys.argv.remove("--smoke-test")
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    QGuiApplication.setHighDpiScaleFactorRoundingPolicy(Qt.HighDpiScaleFactorRoundingPolicy.PassThrough)
    QGuiApplication.setApplicationName("Nightseal")
    QGuiApplication.setOrganizationName("Nightseal")
    application = QApplication(sys.argv)
    application.setFont(QFont("Segoe UI", 10))
    icon = Path(__file__).resolve().parents[1] / "assets" / "nightseal.ico"
    if icon.exists(): application.setWindowIcon(QIcon(str(icon)))
    controller = Controller(application)
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", controller)
    qml = Path(__file__).resolve().parent / "qml" / "Main.qml"
    engine.load(QUrl.fromLocalFile(str(qml)))
    if not engine.rootObjects():
        controller.shutdown(); raise RuntimeError(f"Could not load {qml}")
    window = engine.rootObjects()[0]
    width = max(720, min(3840, int(controller.preferences.get("window_width", 1100))))
    height = max(500, min(2160, int(controller.preferences.get("window_height", 720))))
    window.setWidth(width); window.setHeight(height)
    saved_x, saved_y = controller.preferences.get("window_x"), controller.preferences.get("window_y")
    if isinstance(saved_x, (int, float)) and isinstance(saved_y, (int, float)):
        wanted = QRect(int(saved_x), int(saved_y), width, height)
        screens = application.screens()
        if any(screen.availableGeometry().intersects(wanted) for screen in screens):
            window.setPosition(int(saved_x), int(saved_y))
        elif application.primaryScreen():
            available = application.primaryScreen().availableGeometry()
            window.setPosition(available.x() + max(0, (available.width() - width) // 2),
                               available.y() + max(0, (available.height() - height) // 2))
    normal_geometry = {"x": window.x(), "y": window.y(), "width": width, "height": height}
    geometry_timer = QTimer(); geometry_timer.setSingleShot(True); geometry_timer.setInterval(250)
    def capture_normal_geometry():
        if window.visibility() == QWindow.Visibility.Windowed:
            normal_geometry.update(x=window.x(), y=window.y(), width=window.width(), height=window.height())
    geometry_timer.timeout.connect(capture_normal_geometry)
    def geometry_changed(*_args):
        if window.visibility() == QWindow.Visibility.Windowed: geometry_timer.start()
    window.xChanged.connect(geometry_changed); window.yChanged.connect(geometry_changed)
    window.widthChanged.connect(geometry_changed); window.heightChanged.connect(geometry_changed)
    window.visibilityChanged.connect(geometry_changed)
    if bool(controller.preferences.get("window_maximized", False)):
        QTimer.singleShot(0, window.showMaximized)
    if smoke_test: QTimer.singleShot(1500, application.quit)
    def closing():
        if not smoke_test:
            capture_normal_geometry()
            controller.preferences.update(window_x=normal_geometry["x"], window_y=normal_geometry["y"],
                                          window_width=normal_geometry["width"], window_height=normal_geometry["height"],
                                          window_maximized=window.visibility() == QWindow.Visibility.Maximized)
            controller.store.save_preferences(controller.preferences)
        controller.shutdown()
    application.aboutToQuit.connect(closing)
    sys.exit(application.exec())
