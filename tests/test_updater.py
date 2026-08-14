import shutil
import unittest
import uuid
import zipfile
from pathlib import Path

from secure_tiles.qt_app import _release_asset_name, _safe_extract_release, _version_tuple


class UpdaterTests(unittest.TestCase):
    def fixture(self):
        root = Path.cwd() / f".updater-test-{uuid.uuid4().hex}"
        root.mkdir()
        self.addCleanup(shutil.rmtree, root, True)
        return root

    def test_semantic_version_comparison_parts(self):
        self.assertGreater(_version_tuple("v0.2.0"), _version_tuple("0.1.9"))
        self.assertEqual(_version_tuple("0.1.0"), (0, 1, 0))
        self.assertEqual(_version_tuple("not-a-version"), ())

    def test_release_asset_names_match_packaged_builds(self):
        self.assertEqual(_release_asset_name("0.2.0", True), "Secure-Tiles-Setup-v0.2.0.exe")
        self.assertEqual(_release_asset_name("0.2.0", False), "Secure-Tiles-Portable-v0.2.0.exe")

    def test_release_extraction_rejects_path_traversal(self):
        root = self.fixture()
        archive = root / "bad.zip"
        with zipfile.ZipFile(archive, "w") as bundle:
            bundle.writestr("../outside.txt", "unsafe")
        with self.assertRaises(ValueError):
            _safe_extract_release(archive, root / "stage")
        self.assertFalse((root / "outside.txt").exists())

    def test_release_extraction_accepts_app_layout(self):
        root = self.fixture()
        archive = root / "good.zip"
        with zipfile.ZipFile(archive, "w") as bundle:
            bundle.writestr("main.py", "pass")
            bundle.writestr("secure_tiles/__init__.py", '__version__ = "0.2.0"')
        stage = root / "stage"
        _safe_extract_release(archive, stage)
        self.assertTrue((stage / "main.py").is_file())
        self.assertTrue((stage / "secure_tiles" / "__init__.py").is_file())


if __name__ == "__main__":
    unittest.main()
