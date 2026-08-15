"""Signed server-control protocol shared by clients and relay implementations."""

from __future__ import annotations

import base64
import json
import re
import time
import uuid
from typing import Any

from nacl import exceptions
from nacl.signing import SigningKey, VerifyKey

from .crypto import CryptoError, Identity, PROTOCOL, canonical

SERVER_ACTIONS = {
    "server.create", "server.update", "server.delete", "channel.create", "channel.update", "channel.delete",
    "role.create", "role.update", "role.delete", "member.roles", "invite.create", "invite.revoke",
    "invite.redeem", "message.send",
}
PERMISSIONS = (
    "view_channels", "send_messages", "manage_messages", "manage_channels",
    "create_invites", "manage_roles", "manage_server",
)
DEFAULT_ROLES = (
    {"id": "admin", "name": "Admin", "color": "#f59e0b", "permissions": list(PERMISSIONS)},
    {"id": "member", "name": "Member", "color": "#94a3b8",
     "permissions": ["view_channels", "send_messages"]},
)


def _b64(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii")


def _unb64(value: str) -> bytes:
    try: return base64.urlsafe_b64decode(value.encode("ascii"))
    except Exception as exc: raise CryptoError("Invalid server signature") from exc


def new_server_id() -> str:
    return uuid.uuid4().hex


def normalize_server_name(value: str) -> str:
    name = " ".join(value.strip().split())[:48]
    if not name: raise ValueError("Server names cannot be empty")
    return name


def normalize_channel_name(value: str) -> str:
    name = re.sub(r"[^a-z0-9-]+", "-", value.strip().lower()).strip("-")[:32]
    if not name: raise ValueError("Channel names need letters or numbers")
    return name


def sign_server_action(identity: Identity, action: str, server_id: str, payload: dict[str, Any],
                       *, issued_at: int | None = None, nonce: str | None = None) -> dict[str, Any]:
    if action not in SERVER_ACTIONS: raise ValueError("Unsupported server action")
    unsigned = {"protocol": PROTOCOL, "type": "server-action", "action": action,
                "server_id": server_id, "actor": identity.signing_public,
                "issued_at": int(time.time()) if issued_at is None else int(issued_at),
                "nonce": nonce or uuid.uuid4().hex, "payload": payload}
    signature = SigningKey(identity.signing_private).sign(canonical(unsigned)).signature
    return {**unsigned, "signature": _b64(signature)}


def validate_server_action(value: dict[str, Any], *, now: int | None = None) -> dict[str, Any]:
    try:
        unsigned = {key: value[key] for key in
                    ("protocol", "type", "action", "server_id", "actor", "issued_at", "nonce", "payload")}
        if unsigned["protocol"] != PROTOCOL or unsigned["type"] != "server-action":
            raise CryptoError("Unsupported server action format")
        if unsigned["action"] not in SERVER_ACTIONS or not re.fullmatch(r"[0-9a-f]{32}", str(unsigned["server_id"])):
            raise CryptoError("Invalid server action")
        if not isinstance(unsigned["payload"], dict) or not re.fullmatch(r"[0-9a-f]{32}", str(unsigned["nonce"])):
            raise CryptoError("Invalid server action")
        if abs((int(time.time()) if now is None else now) - int(unsigned["issued_at"])) > 300:
            raise CryptoError("Server action has expired")
        VerifyKey(_unb64(str(unsigned["actor"]))).verify(canonical(unsigned), _unb64(str(value["signature"])))
        return unsigned
    except CryptoError: raise
    except (KeyError, TypeError, ValueError, exceptions.CryptoError) as exc:
        raise CryptoError("Invalid or forged server action") from exc


def role_permissions(value: Any) -> list[str]:
    if not isinstance(value, list): raise ValueError("Role permissions must be a list")
    result = [permission for permission in PERMISSIONS if permission in value]
    if len(result) != len(set(map(str, value))): raise ValueError("Role contains unsupported permissions")
    return result
