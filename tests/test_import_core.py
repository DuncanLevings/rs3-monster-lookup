"""Verify complete, repeatable imports without touching a real data checkout."""
from pathlib import Path
import importlib.util
import json
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "import_core", Path(__file__).resolve().parents[1] / "tools/import_core.py"
)
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)


class ImportCoreTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent)
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.project = self.base / "plugin"
        self.source = self.base / "core"
        self.put(self.project, "tools/PLUGIN_NOTICES.txt", "Local attribution\n")
        self.put(self.project, "src/data/library/removed.lua", "old")
        self.put(self.project, "types/removed.lua", "old")
        self.put(self.source, "plugin.json", '{"version": "1.2.3"}')
        self.put(self.source, "src/api.lua", 'return require("src/records")\n')
        self.put(self.source, "src/records.lua", "return {}\n")
        self.put(self.source, "types/records.lua", "-- current types\n")
        self.put(self.source, "THIRD_PARTY_NOTICES.txt", "Upstream attribution\n")

    @staticmethod
    def put(root, relative, text):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def snapshot(self):
        return {
            path.relative_to(self.project).as_posix(): path.read_bytes()
            for path in self.project.rglob("*") if path.is_file()
        }

    def test_import_replaces_removed_files_types_and_shipped_notices(self):
        importer.import_core(self.project, self.source)
        self.assertFalse((self.project / "src/data/library/removed.lua").exists())
        self.assertFalse((self.project / "types/removed.lua").exists())
        self.assertEqual(
            (self.project / "src/data/library/api.lua").read_text(),
            'return require("src/data/library/records")\n',
        )
        self.assertEqual((self.project / "types/records.lua").read_text(), "-- current types\n")
        notices = (self.project / "THIRD_PARTY_NOTICES.txt").read_text()
        self.assertIn("Local attribution", notices)
        self.assertIn("Upstream attribution", notices)
        manifest = json.loads((self.project / "tools/library_snapshot.json").read_text())
        self.assertEqual(manifest["version"], "1.2.3")
        self.assertEqual(len(manifest["source_sha256"]), 2)
        self.assertIn("records.lua", manifest["types_sha256"])

    def test_reimport_is_identical(self):
        importer.import_core(self.project, self.source)
        first = self.snapshot()
        importer.import_core(self.project, self.source)
        self.assertEqual(self.snapshot(), first)

    def test_invalid_source_does_not_change_the_existing_snapshot(self):
        (self.source / "src/api.lua").unlink()
        first = self.snapshot()
        with self.assertRaises(ValueError):
            importer.import_core(self.project, self.source)
        self.assertEqual(self.snapshot(), first)

    def test_import_rejects_its_own_project(self):
        first = self.snapshot()
        with self.assertRaises(ValueError):
            importer.import_core(self.project, self.project)
        self.assertEqual(self.snapshot(), first)


if __name__ == "__main__":
    unittest.main()
