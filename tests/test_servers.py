import unittest

from secure_tiles.crypto import CryptoError, Identity
from secure_tiles.servers import (PERMISSIONS, new_server_id, normalize_channel_name,
                                  role_permissions, sign_server_action, validate_server_action)


class ServerProtocolTests(unittest.TestCase):
    def test_signed_server_action_round_trip_and_tampering(self):
        identity = Identity.generate(); server_id = new_server_id()
        action = sign_server_action(identity, "channel.create", server_id, {"name": "general", "type": "text"}, issued_at=100)
        self.assertEqual(validate_server_action(action, now=100)["actor"], identity.signing_public)
        action["payload"]["name"] = "forged"
        with self.assertRaises(CryptoError): validate_server_action(action, now=100)

    def test_server_actions_expire_and_reject_unknown_actions(self):
        identity = Identity.generate(); server_id = new_server_id()
        action = sign_server_action(identity, "server.update", server_id, {"name": "Test"}, issued_at=100)
        with self.assertRaises(CryptoError): validate_server_action(action, now=401)
        with self.assertRaises(ValueError): sign_server_action(identity, "server.destroy", server_id, {})

    def test_channel_names_and_permissions_are_bounded(self):
        self.assertEqual(normalize_channel_name(" General Chat! "), "general-chat")
        self.assertEqual(role_permissions(list(PERMISSIONS)), list(PERMISSIONS))
        with self.assertRaises(ValueError): role_permissions(["view_channels", "become_owner"])


if __name__ == "__main__": unittest.main()
