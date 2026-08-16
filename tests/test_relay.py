import json
import base64
import threading
import unittest
import uuid
from http.server import ThreadingHTTPServer
from pathlib import Path

from relay_server import Database, Handler
from secure_tiles.crypto import Identity, encrypt_message, public_card, validate_card
from secure_tiles.relay import RelayClient, RelayError
from secure_tiles.servers import new_server_id, sign_server_action


class RelayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db_path = Path.cwd() / f"relay-test-{uuid.uuid4().hex}.db"
        Handler.db = Database(cls.db_path)
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True); cls.thread.start()
        cls.client = RelayClient(f"http://127.0.0.1:{cls.server.server_port}")

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); Handler.db.connection.close()
        cls.db_path.unlink(missing_ok=True)

    def test_registration_lookup_and_delivery(self):
        alice, bob = Identity.generate(), Identity.generate()
        alice_card, bob_card = public_card(alice, "alice_test"), public_card(bob, "bob_test")
        self.client.register(alice_card); self.client.register(bob_card)
        self.assertEqual(self.client.lookup("alice_test")["signing_key"], alice_card["signing_key"])
        packet = encrypt_message(alice, validate_card(bob_card), "hello")
        self.client.send(packet)
        self.assertEqual(self.client.inbox(bob.encryption_public)[0]["id"], packet["id"])
        self.assertEqual(self.client.inbox(bob.encryption_public), [])

    def test_username_cannot_be_reassigned(self):
        first, second = Identity.generate(), Identity.generate()
        self.client.register(public_card(first, "pinned_name"))
        with self.assertRaises(RelayError): self.client.register(public_card(second, "pinned_name"))

    def test_username_is_case_insensitively_unique(self):
        first, second = Identity.generate(), Identity.generate()
        self.client.register(public_card(first, "Case_Name"))
        with self.assertRaises(RelayError): self.client.register(public_card(second, "case_name"))

    def test_encrypted_typing_state_is_returned_with_inbox(self):
        sender, recipient = Identity.generate(), Identity.generate()
        sender_card = public_card(sender, "typing_sender")
        recipient_card = public_card(recipient, "typing_recipient")
        self.client.register(sender_card); self.client.register(recipient_card)
        packet = encrypt_message(sender, validate_card(recipient_card), "\0secure-tiles-typing:on")
        self.client.send_typing(packet)
        state = self.client.inbox_state(recipient.encryption_public)
        self.assertEqual(state["typing"][0]["id"], packet["id"])
        self.assertEqual(state["messages"], [])

    def test_encrypted_presence_state_is_returned_with_inbox(self):
        sender, recipient = Identity.generate(), Identity.generate()
        sender_card = public_card(sender, "presence_sender")
        recipient_card = public_card(recipient, "presence_recipient")
        self.client.register(sender_card); self.client.register(recipient_card)
        packet = encrypt_message(sender, validate_card(recipient_card), "\0secure-tiles-presence:Do Not Disturb")
        self.client.send_presence(packet)
        state = self.client.inbox_state(recipient.encryption_public)
        self.assertEqual(state["presence"][0]["id"], packet["id"])
        self.assertEqual(state["messages"], [])

    def test_signed_server_creation_invite_and_membership(self):
        owner, member = Identity.generate(), Identity.generate()
        owner_card, member_card = public_card(owner, "server_owner"), public_card(member, "server_member")
        self.client.register(owner_card); self.client.register(member_card)
        server_id = new_server_id()
        created = self.client.server_action(sign_server_action(owner, "server.create", server_id,
                                                               {"name": "Test Server", "owner_card": owner_card, "accent": "#5865f2"}))
        self.assertEqual(created["name"], "Test Server"); self.assertEqual(created["channels"][0]["type"], "text")
        code = uuid.uuid4().hex[:12]
        self.client.server_action(sign_server_action(owner, "invite.create", server_id,
                                                     {"code": code, "role_id": "member", "uses": 1}))
        joined = self.client.server_action(sign_server_action(member, "invite.redeem", server_id,
                                                              {"code": code, "member_card": member_card}))
        self.assertEqual(len(joined["members"]), 2)
        self.assertEqual(self.client.servers(member.signing_public)[0]["id"], server_id)

    def test_regular_server_member_cannot_manage_channels(self):
        owner, member = Identity.generate(), Identity.generate()
        owner_card, member_card = public_card(owner, "permission_owner"), public_card(member, "permission_member")
        self.client.register(owner_card); self.client.register(member_card); server_id = new_server_id(); code = uuid.uuid4().hex[:12]
        self.client.server_action(sign_server_action(owner, "server.create", server_id, {"name": "Permissions", "owner_card": owner_card}))
        self.client.server_action(sign_server_action(owner, "invite.create", server_id, {"code": code, "role_id": "member"}))
        self.client.server_action(sign_server_action(member, "invite.redeem", server_id, {"code": code, "member_card": member_card}))
        with self.assertRaises(RelayError):
            self.client.server_action(sign_server_action(member, "channel.create", server_id, {"name": "staff", "type": "text"}))

    def test_server_owner_can_create_category_and_move_channel(self):
        owner = Identity.generate(); card = public_card(owner, "category_owner"); self.client.register(card); server_id = new_server_id()
        server = self.client.server_action(sign_server_action(owner, "server.create", server_id, {"name": "Categories", "owner_card": card}))
        channel = next(item for item in server["channels"] if item["type"] == "text")
        server = self.client.server_action(sign_server_action(owner, "channel.create", server_id, {"name": "Important", "type": "voice", "topic": "category"}))
        category = next(item for item in server["channels"] if item["type"] == "voice" and item["topic"] == "category")
        moved = self.client.server_action(sign_server_action(owner, "channel.update", server_id,
                                                              {"channel_id": channel["id"], "name": channel["name"], "category_id": category["id"]}))
        self.assertEqual(next(item for item in moved["channels"] if item["id"] == channel["id"])["topic"], f"category:{category['id']}")

    def test_server_owner_can_rename_built_in_roles(self):
        owner = Identity.generate(); card = public_card(owner, "role_rename_owner"); self.client.register(card); server_id = new_server_id()
        server = self.client.server_action(sign_server_action(owner, "server.create", server_id, {"name": "Roles", "owner_card": card}))
        admin = next(role for role in server["roles"] if role["id"] == "admin")
        updated = self.client.server_action(sign_server_action(owner, "role.update", server_id, {"role_id": "admin", "name": "Moderators", "color": admin["color"], "permissions": admin["permissions"]}))
        self.assertEqual(next(role for role in updated["roles"] if role["id"] == "admin")["name"], "Moderators")

    def test_server_message_fanout_is_permission_checked(self):
        owner, member = Identity.generate(), Identity.generate()
        owner_card, member_card = public_card(owner, "fanout_owner"), public_card(member, "fanout_member")
        self.client.register(owner_card); self.client.register(member_card); server_id = new_server_id(); code = uuid.uuid4().hex[:12]
        server = self.client.server_action(sign_server_action(owner, "server.create", server_id, {"name": "Fanout", "owner_card": owner_card}))
        self.client.server_action(sign_server_action(owner, "invite.create", server_id, {"code": code, "role_id": "member"}))
        self.client.server_action(sign_server_action(member, "invite.redeem", server_id, {"code": code, "member_card": member_card}))
        packet = encrypt_message(owner, validate_card(member_card), "encrypted channel payload")
        action = sign_server_action(owner, "message.send", server_id, {"channel_id": server["channels"][0]["id"], "packets": [packet]})
        self.client.send_server_message(action)
        self.assertEqual(self.client.inbox(member.encryption_public)[0]["id"], packet["id"])
        outsider = Identity.generate(); outsider_card = public_card(outsider, "fanout_outsider"); self.client.register(outsider_card)
        bad_packet = encrypt_message(owner, validate_card(outsider_card), "leak")
        with self.assertRaises(RelayError):
            self.client.send_server_message(sign_server_action(owner, "message.send", server_id, {"channel_id": server["channels"][0]["id"], "packets": [bad_packet]}))

    def test_server_owner_can_permanently_delete_server(self):
        owner = Identity.generate(); owner_card = public_card(owner, "delete_owner")
        self.client.register(owner_card); server_id = new_server_id()
        self.client.server_action(sign_server_action(owner, "server.create", server_id, {"name": "Disposable", "owner_card": owner_card}))
        result = self.client.server_action(sign_server_action(owner, "server.delete", server_id, {}))
        self.assertEqual(result, {"deleted": True, "id": server_id})
        with self.assertRaises(RelayError): self.client.server(server_id)

    def test_invite_codes_are_globally_unique_and_can_be_non_expiring(self):
        first, second = Identity.generate(), Identity.generate()
        first_card, second_card = public_card(first, "invite_unique_one"), public_card(second, "invite_unique_two")
        self.client.register(first_card); self.client.register(second_card)
        first_id, second_id, code = new_server_id(), new_server_id(), "NeverDuplicateMe"
        self.client.server_action(sign_server_action(first, "server.create", first_id, {"name": "One", "owner_card": first_card}))
        self.client.server_action(sign_server_action(second, "server.create", second_id, {"name": "Two", "owner_card": second_card}))
        self.client.server_action(sign_server_action(first, "invite.create", first_id, {"code": code, "role_id": "member", "expires": 0}))
        with self.assertRaises(RelayError):
            self.client.server_action(sign_server_action(second, "invite.create", second_id, {"code": code, "role_id": "member", "expires": 0}))

    def test_chunked_attachment_upload_can_resume_and_download(self):
        transfer_id, token = uuid.uuid4().hex, base64.urlsafe_b64encode(b"token" * 8).decode("ascii")
        self.client.begin_attachment(transfer_id, token, "recipient-key", 5, 2)
        first = base64.urlsafe_b64encode(b"encrypted-one").decode("ascii")
        second = base64.urlsafe_b64encode(b"encrypted-two").decode("ascii")
        self.client.upload_attachment_chunk(transfer_id, token, 0, first)
        self.assertEqual(self.client.attachment_status(transfer_id, token), {0})
        self.client.begin_attachment(transfer_id, token, "recipient-key", 5, 2)
        self.client.upload_attachment_chunk(transfer_id, token, 1, second)
        self.assertEqual(base64.urlsafe_b64decode(self.client.download_attachment_chunk(transfer_id, token, 0)), b"encrypted-one")
        self.assertEqual(base64.urlsafe_b64decode(self.client.download_attachment_chunk(transfer_id, token, 1)), b"encrypted-two")
        self.client.complete_attachment(transfer_id, token)
        with self.assertRaises(RelayError):
            self.client.download_attachment_chunk(transfer_id, token, 0)
