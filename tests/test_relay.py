import json
import threading
import unittest
import uuid
from http.server import ThreadingHTTPServer
from pathlib import Path

from relay_server import Database, Handler
from secure_tiles.crypto import Identity, encrypt_message, public_card, validate_card
from secure_tiles.relay import RelayClient, RelayError


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
