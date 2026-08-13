import unittest

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
