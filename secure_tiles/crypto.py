"""Small, auditable wrapper around libsodium via PyNaCl.

This module deliberately contains no home-grown cryptographic primitives.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import time
import uuid
from dataclasses import dataclass
from typing import Any

from nacl import exceptions, pwhash, secret, utils
from nacl.public import Box, PrivateKey, PublicKey
from nacl.signing import SigningKey, VerifyKey

PROTOCOL = "secure-tiles-v1"
MAX_ATTACHMENT_COUNT = 5
MAX_ATTACHMENT_BYTES = 50 * 1024 * 1024


class CryptoError(ValueError):
    """Raised when encrypted or signed data cannot be trusted."""


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii")


def _unb64(data: str) -> bytes:
    try:
        return base64.urlsafe_b64decode(data.encode("ascii"))
    except Exception as exc:
        raise CryptoError("Invalid base64 data") from exc


def canonical(data: dict[str, Any]) -> bytes:
    return json.dumps(data, sort_keys=True, separators=(",", ":")).encode("utf-8")


def fingerprint(public_key: str) -> str:
    digest = hashlib.sha256(_unb64(public_key)).hexdigest().upper()
    return " ".join(digest[i : i + 4] for i in range(0, 32, 4))


@dataclass(frozen=True)
class Identity:
    encryption_private: bytes
    signing_private: bytes

    @classmethod
    def generate(cls) -> "Identity":
        return cls(bytes(PrivateKey.generate()), bytes(SigningKey.generate()))

    @property
    def encryption_public(self) -> str:
        return _b64(bytes(PrivateKey(self.encryption_private).public_key))

    @property
    def signing_public(self) -> str:
        return _b64(bytes(SigningKey(self.signing_private).verify_key))

    @property
    def safety_number(self) -> str:
        return fingerprint(self.signing_public)


def lock_identity(identity: Identity, passphrase: str) -> dict[str, str | int]:
    if len(passphrase) < 10:
        raise CryptoError("Use a passphrase of at least 10 characters")
    salt = utils.random(pwhash.argon2id.SALTBYTES)
    key = pwhash.argon2id.kdf(
        secret.SecretBox.KEY_SIZE,
        passphrase.encode("utf-8"),
        salt,
        opslimit=pwhash.argon2id.OPSLIMIT_MODERATE,
        memlimit=pwhash.argon2id.MEMLIMIT_MODERATE,
    )
    plaintext = canonical({
        "encryption_private": _b64(identity.encryption_private),
        "signing_private": _b64(identity.signing_private),
    })
    encrypted = bytes(secret.SecretBox(key).encrypt(plaintext))
    return {"version": 1, "salt": _b64(salt), "ciphertext": _b64(encrypted)}


def unlock_identity(vault: dict[str, Any], passphrase: str) -> Identity:
    try:
        salt = _unb64(vault["salt"])
        key = pwhash.argon2id.kdf(
            secret.SecretBox.KEY_SIZE,
            passphrase.encode("utf-8"),
            salt,
            opslimit=pwhash.argon2id.OPSLIMIT_MODERATE,
            memlimit=pwhash.argon2id.MEMLIMIT_MODERATE,
        )
        raw = secret.SecretBox(key).decrypt(_unb64(vault["ciphertext"]))
        data = json.loads(raw)
        return Identity(_unb64(data["encryption_private"]), _unb64(data["signing_private"]))
    except (KeyError, ValueError, exceptions.CryptoError, json.JSONDecodeError) as exc:
        raise CryptoError("Wrong passphrase or damaged identity vault") from exc


def public_card(identity: Identity, name: str) -> dict[str, str]:
    unsigned = {
        "protocol": PROTOCOL,
        "type": "contact",
        "name": name.strip()[:64],
        "encryption_key": identity.encryption_public,
        "signing_key": identity.signing_public,
    }
    signature = SigningKey(identity.signing_private).sign(canonical(unsigned)).signature
    return {**unsigned, "signature": _b64(signature)}


def validate_card(card: dict[str, Any]) -> dict[str, str]:
    try:
        signature = _unb64(str(card["signature"]))
        unsigned = {key: card[key] for key in ("protocol", "type", "name", "encryption_key", "signing_key")}
        VerifyKey(_unb64(str(card["signing_key"]))).verify(canonical(unsigned), signature)
        PublicKey(_unb64(str(card["encryption_key"])))
        if card["protocol"] != PROTOCOL or card["type"] != "contact":
            raise CryptoError("Unsupported contact card")
        return {key: str(value) for key, value in unsigned.items()}
    except (KeyError, ValueError, exceptions.CryptoError) as exc:
        raise CryptoError("Invalid or forged contact card") from exc


def _validated_attachments(values: Any) -> list[dict[str, Any]]:
    if values is None:
        return []
    if not isinstance(values, list) or len(values) > MAX_ATTACHMENT_COUNT:
        raise CryptoError(f"A message can contain up to {MAX_ATTACHMENT_COUNT} files")
    result, total = [], 0
    for value in values:
        try:
            name = str(value["name"]).replace("\\", "/").rsplit("/", 1)[-1].strip()[:180]
            mime = str(value.get("mime", "application/octet-stream"))[:100]
        except (KeyError, TypeError, ValueError, UnicodeEncodeError) as exc:
            raise CryptoError("Attachment data is invalid") from exc
        if "data" in value:
            try:
                data = str(value["data"])
                raw = base64.b64decode(data.encode("ascii"), altchars=b"-_", validate=True)
            except (ValueError, UnicodeEncodeError) as exc:
                raise CryptoError("Attachment data is invalid") from exc
            if not raw: raise CryptoError("Attachments must have content")
            normalized = {"name": name, "mime": mime, "size": len(raw), "data": data}
        else:
            try:
                size, chunks = int(value["size"]), int(value["chunks"])
                transfer_id, token, key = str(value["transfer_id"]), str(value["token"]), str(value["key"])
                digest = str(value["sha256"])
                token_bytes, key_bytes = _unb64(token), _unb64(key)
            except (KeyError, TypeError, ValueError) as exc:
                raise CryptoError("Attachment transfer metadata is invalid") from exc
            if (not 1 <= size <= MAX_ATTACHMENT_BYTES or not 1 <= chunks <= 50 or len(transfer_id) > 64
                    or len(token_bytes) < 16 or len(key_bytes) != secret.SecretBox.KEY_SIZE
                    or not re.fullmatch(r"[0-9a-f]{64}", digest)):
                raise CryptoError("Attachment transfer metadata is invalid")
            normalized = {"name": name, "mime": mime, "size": size, "transfer_id": transfer_id,
                          "token": token, "key": key, "chunks": chunks, "sha256": digest}
        if not name: raise CryptoError("Attachments must have a name")
        total += int(normalized["size"])
        if total > MAX_ATTACHMENT_BYTES:
            raise CryptoError("Attachments are limited to 50 MB per message")
        result.append(normalized)
    return result


def encrypt_message(identity: Identity, recipient: dict[str, str], text: str,
                    attachments: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    files = _validated_attachments(attachments)
    if len(text.encode("utf-8")) > 64_000 or (not text and not files):
        raise CryptoError("A message needs text or an attachment and text is limited to 64,000 bytes")
    inner = {
        "id": str(uuid.uuid4()),
        "sent_at": int(time.time()),
        "text": text,
        "sender_encryption_key": identity.encryption_public,
        "sender_signing_key": identity.signing_public,
    }
    if files:
        inner["attachments"] = files
    signature = SigningKey(identity.signing_private).sign(canonical(inner)).signature
    signed = canonical({**inner, "signature": _b64(signature)})
    box = Box(PrivateKey(identity.encryption_private), PublicKey(_unb64(recipient["encryption_key"])))
    encrypted = bytes(box.encrypt(signed))
    return {
        "protocol": PROTOCOL,
        "type": "message",
        "id": inner["id"],
        "to": recipient["encryption_key"],
        "from": identity.encryption_public,
        "ciphertext": _b64(encrypted),
    }


def decrypt_message(identity: Identity, envelope: dict[str, Any], sender: dict[str, str]) -> dict[str, Any]:
    try:
        if envelope["protocol"] != PROTOCOL or envelope["type"] != "message":
            raise CryptoError("Unsupported message format")
        if envelope["to"] != identity.encryption_public:
            raise CryptoError("This message was encrypted for another identity")
        if envelope["from"] != sender["encryption_key"]:
            raise CryptoError("Sender encryption key does not match the saved contact")
        box = Box(PrivateKey(identity.encryption_private), PublicKey(_unb64(sender["encryption_key"])))
        inner = json.loads(box.decrypt(_unb64(str(envelope["ciphertext"]))))
        if envelope.get("id") != inner.get("id"):
            raise CryptoError("Message identifier was altered")
        signature = _unb64(inner.pop("signature"))
        if inner["sender_encryption_key"] != sender["encryption_key"] or inner["sender_signing_key"] != sender["signing_key"]:
            raise CryptoError("Sender identity mismatch")
        VerifyKey(_unb64(sender["signing_key"])).verify(canonical(inner), signature)
        inner["attachments"] = _validated_attachments(inner.get("attachments"))
        if abs(int(time.time()) - int(inner["sent_at"])) > 30 * 24 * 3600:
            raise CryptoError("Message timestamp is outside the accepted 30-day window")
        return inner
    except CryptoError:
        raise
    except (KeyError, ValueError, TypeError, exceptions.CryptoError, json.JSONDecodeError) as exc:
        raise CryptoError("Message is corrupt, forged, or from the wrong sender") from exc
