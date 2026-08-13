"""Small, auditable wrapper around libsodium via PyNaCl.

This module deliberately contains no home-grown cryptographic primitives.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import time
import uuid
from dataclasses import dataclass
from typing import Any

from nacl import exceptions, pwhash, secret, utils
from nacl.public import Box, PrivateKey, PublicKey
from nacl.signing import SigningKey, VerifyKey

PROTOCOL = "secure-tiles-v1"


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


def encrypt_message(identity: Identity, recipient: dict[str, str], text: str) -> dict[str, Any]:
    if not text or len(text.encode("utf-8")) > 64_000:
        raise CryptoError("Message must be between 1 and 64,000 bytes")
    inner = {
        "id": str(uuid.uuid4()),
        "sent_at": int(time.time()),
        "text": text,
        "sender_encryption_key": identity.encryption_public,
        "sender_signing_key": identity.signing_public,
    }
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
        if abs(int(time.time()) - int(inner["sent_at"])) > 30 * 24 * 3600:
            raise CryptoError("Message timestamp is outside the accepted 30-day window")
        return inner
    except CryptoError:
        raise
    except (KeyError, ValueError, TypeError, exceptions.CryptoError, json.JSONDecodeError) as exc:
        raise CryptoError("Message is corrupt, forged, or from the wrong sender") from exc
