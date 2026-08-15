import base64
import shutil
import unittest
import uuid
import json
from pathlib import Path

from secure_tiles.store import Store


class StoreTests(unittest.TestCase):
    def test_server_messages_are_partitioned_by_channel(self):
        directory = Path.cwd() / "tests" / f"store-test-{uuid.uuid4().hex}"
        directory.mkdir()
        try:
            store = Store(directory)
            store.add_server_message("one", "server", "general", "alice", "in", 1, "hello")
            store.add_server_message("two", "server", "staff", "bob", "out", 2, "secret")
            self.assertEqual([row["plaintext"] for row in store.server_messages("server", "general")], ["hello"])
            store.db.close()
        finally:
            shutil.rmtree(directory)

    def test_attachment_is_written_to_local_history(self):
        directory = Path.cwd() / "tests" / f"store-test-{uuid.uuid4().hex}"
        directory.mkdir()
        try:
            store = Store(directory)
            attachment = {"name": "notes.txt", "mime": "text/plain", "size": 5,
                          "data": base64.urlsafe_b64encode(b"hello").decode("ascii")}
            store.add_message("message-1", "contact", "in", 1, "", [attachment])
            row = store.message("message-1")
            self.assertIsNotNone(row)
            saved = __import__("json").loads(row["attachments"])[0]
            self.assertEqual(Path(saved["path"]).read_bytes(), b"hello")
            store.db.close()
        finally:
            shutil.rmtree(directory)

    def test_remote_attachment_manifest_survives_until_download(self):
        directory = Path.cwd() / "tests" / f"store-test-{uuid.uuid4().hex}"
        directory.mkdir()
        try:
            store = Store(directory)
            manifest = {"name": "large.bin", "mime": "application/octet-stream", "size": 100,
                        "transfer_id": "transfer", "token": "token", "key": "key", "chunks": 1, "sha256": "a" * 64}
            store.add_message("message-2", "contact", "in", 1, "file", [manifest])
            self.assertEqual(json.loads(store.message("message-2")["attachments"])[0]["transfer_id"], "transfer")
            store.db.close()
        finally:
            shutil.rmtree(directory)


if __name__ == "__main__":
    unittest.main()
