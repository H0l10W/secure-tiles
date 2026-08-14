import unittest
import base64

from secure_tiles.crypto import (
    CryptoError, Identity, decrypt_message, encrypt_message, lock_identity,
    public_card, unlock_identity, validate_card,
)


class CryptoTests(unittest.TestCase):
    def setUp(self):
        self.alice, self.bob = Identity.generate(), Identity.generate()
        self.alice_card = validate_card(public_card(self.alice, "Alice"))
        self.bob_card = validate_card(public_card(self.bob, "Bob"))

    def test_round_trip_and_signature(self):
        packet = encrypt_message(self.alice, self.bob_card, "hello")
        self.assertEqual(decrypt_message(self.bob, packet, self.alice_card)["text"], "hello")

    def test_attachment_only_round_trip(self):
        attachment = {"name": "photo.png", "mime": "image/png", "size": 4,
                      "data": base64.urlsafe_b64encode(b"test").decode("ascii")}
        packet = encrypt_message(self.alice, self.bob_card, "", [attachment])
        message = decrypt_message(self.bob, packet, self.alice_card)
        self.assertEqual(message["text"], "")
        self.assertEqual(message["attachments"][0]["name"], "photo.png")
        self.assertEqual(base64.urlsafe_b64decode(message["attachments"][0]["data"]), b"test")

    def test_empty_message_and_invalid_attachment_are_rejected(self):
        with self.assertRaises(CryptoError):
            encrypt_message(self.alice, self.bob_card, "")
        with self.assertRaises(CryptoError):
            encrypt_message(self.alice, self.bob_card, "file", [{"name": "bad.bin", "data": "not base64"}])

    def test_chunked_attachment_manifest_round_trip(self):
        manifest = {"name": "archive.zip", "mime": "application/zip", "size": 1234,
                    "transfer_id": "transfer-1", "token": base64.urlsafe_b64encode(b"t" * 32).decode("ascii"),
                    "key": base64.urlsafe_b64encode(b"k" * 32).decode("ascii"), "chunks": 1,
                    "sha256": "a" * 64}
        packet = encrypt_message(self.alice, self.bob_card, "file", [manifest])
        self.assertEqual(decrypt_message(self.bob, packet, self.alice_card)["attachments"], [manifest])

    def test_tampering_is_rejected(self):
        packet = encrypt_message(self.alice, self.bob_card, "hello")
        packet["ciphertext"] = packet["ciphertext"][:-3] + "AAA"
        with self.assertRaises(CryptoError):
            decrypt_message(self.bob, packet, self.alice_card)

    def test_wrong_recipient_is_rejected(self):
        packet = encrypt_message(self.alice, self.bob_card, "hello")
        with self.assertRaises(CryptoError):
            decrypt_message(Identity.generate(), packet, self.alice_card)

    def test_vault_round_trip_and_wrong_password(self):
        vault = lock_identity(self.alice, "correct horse battery staple")
        restored = unlock_identity(vault, "correct horse battery staple")
        self.assertEqual(restored.signing_public, self.alice.signing_public)
        with self.assertRaises(CryptoError):
            unlock_identity(vault, "wrong password")


if __name__ == "__main__":
    unittest.main()
