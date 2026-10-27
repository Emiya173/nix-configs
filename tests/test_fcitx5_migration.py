"""Exercise Fcitx5 file handover only in disposable homes under /tmp."""

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest


MODULE = Path(os.environ.get(
    "FCITX5_MIGRATION_MODULE", Path(__file__).parents[1] / "scripts/migrate-fcitx5.py",
))
spec = importlib.util.spec_from_file_location("fcitx5_migration", MODULE)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class Fcitx5MigrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="fcitx5-migration-", dir="/tmp")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.rime = self.root / "home/.local/share/fcitx5/rime"
        self.rime.mkdir(parents=True)
        self.state = self.root / "home/.local/state/fcitx5"
        self.target = self.rime / "rime_ice.dict.yaml"
        self.source = self.root / "packaged-rime_ice.dict.yaml"
        self.source.write_text("locked dictionary")
        self.files = [{"target": str(self.target), "source": str(self.source)}]

    def test_preserves_old_dictionary_and_leaves_learning_data_untouched(self):
        self.target.write_text("import_tables:\n  - moegirl\n")
        for name in ("rime_ice.userdb/data", "build/rime_ice.table.bin", "sync/user/data",
                     "default.custom.yaml.hm-backup"):
            path = self.rime / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("keep")
        backup = migration.migrate(self.files, self.state)
        record = json.loads((backup / "manifest.json").read_text())[0]
        self.assertIn("moegirl", Path(record["backup"]).read_text())
        self.assertFalse(self.target.exists())
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
        self.assertEqual(sorted(path.read_text() for path in self.rime.rglob("*") if path.is_file()),
                         ["keep", "keep", "keep", "keep"])
        self.target.symlink_to(self.source)  # Hjem links the declared file next.
        self.assertIsNone(migration.migrate(self.files, self.state))
        self.assertEqual(len(list(self.state.iterdir())), 1)

    def test_preserves_foreign_and_dangling_symlinks(self):
        self.target.symlink_to("missing-old-dictionary")
        backup = migration.migrate(self.files, self.state)
        saved = backup / "0-rime_ice.dict.yaml"
        self.assertTrue(saved.is_symlink())
        self.assertEqual(os.readlink(saved), "missing-old-dictionary")

    def test_repeated_edits_get_separate_backups(self):
        backups = []
        for text in ("first edit", "second edit"):
            self.target.write_text(text)
            backups.append(migration.migrate(self.files, self.state))
        self.assertNotEqual(*backups)
        self.assertEqual([(backup / "0-rime_ice.dict.yaml").read_text() for backup in backups],
                         ["first edit", "second edit"])

    def test_preflights_all_paths_before_moving_any_file(self):
        self.target.write_text("keep")
        directory = self.rime / "default.custom.yaml"
        directory.mkdir()
        files = self.files + [{"target": str(directory), "source": str(self.source)}]
        with self.assertRaises(ValueError):
            migration.migrate(files, self.state)
        self.assertEqual(self.target.read_text(), "keep")
        self.assertFalse(self.state.exists())

    def test_rejects_symlinked_parents(self):
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "profile").write_text("keep")
        link = self.rime / "redirect"
        link.symlink_to(outside)
        with self.assertRaises(ValueError):
            migration.migrate([{"target": str(link / "profile"), "source": str(self.source)}], self.state)
        self.assertEqual((outside / "profile").read_text(), "keep")


if __name__ == "__main__":
    unittest.main()
