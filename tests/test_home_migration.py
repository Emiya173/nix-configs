"""Exercise migration against disposable homes only; never use the real $HOME."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


MODULE = Path(os.environ.get(
    "HOME_MIGRATION_MODULE",
    Path(__file__).parents[1] / "scripts/migrate-home-manager.py",
))
spec = importlib.util.spec_from_file_location("home_migration", MODULE)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)
HM_ROOT = "/nix/store/" + "a" * 32 + "-home-manager-files/"


class HomeMigrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hm-migration-test-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.allowlist = self.root / "allowlist.json"
        self.state = self.home / ".local/state/home-manager-migration"

    def manifest(self, targets):
        self.allowlist.write_text(json.dumps({"version": 1, "host": "test", "targets": targets}))

    def link(self, relative, target=None):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.symlink_to(target if target is not None else HM_ROOT + relative)
        return path

    def migrate(self):
        return migration.migrate(self.home, self.allowlist)

    def old_files(self, targets):
        files = self.root / "old-home-files"
        for relative in targets:
            source = files / relative
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("old managed configuration")
        return files

    def test_rollback_preserves_edits_and_existing_backups_then_can_migrate_again(self):
        targets = [".config/git/config", ".config/atuin/config.toml", ".gtkrc-2.0"]
        self.manifest(targets)
        files = self.old_files(targets)
        for target in targets:
            self.link(target)
        forward = self.migrate()
        git = self.link(targets[0], "/nix/store/" + "b" * 32 + "-git-config")
        atuin = self.home / targets[1]
        atuin.write_text("changes since migration")
        previous_backup = atuin.with_suffix(".toml.hm-backup")
        previous_backup.write_text("older backup; keep")
        untouched = self.home / "unrelated"
        untouched.write_text("private user data")

        before = set(self.state.iterdir())
        preview = migration.migrate(self.home, self.allowlist, rollback_files=files, apply=False)
        self.assertEqual(preview["conflicts"], sorted(targets[:2]))
        self.assertEqual(set(self.state.iterdir()), before)
        self.assertTrue(git.is_symlink())
        result = migration.migrate(self.home, self.allowlist, rollback_files=files)
        saved = Path(result["backup"])
        self.assertEqual(result["moved"], 2)
        self.assertEqual((saved / "files" / targets[1]).read_text(), "changes since migration")
        self.assertEqual(os.readlink(saved / "files" / targets[0]), "/nix/store/" + "b" * 32 + "-git-config")
        self.assertEqual(previous_backup.read_text(), "older backup; keep")
        self.assertEqual(untouched.read_text(), "private user data")
        audit = json.loads((saved / "manifest.json").read_text())
        self.assertEqual(audit["operation"], "prepare-rollback")
        self.assertEqual(audit["rollbackFiles"], str(files))
        self.assertEqual(migration.migrate(self.home, self.allowlist, rollback_files=files)["moved"], 0)
        # The old activation now has empty destinations, so existing hm-backup
        # files cannot block it. Its links can be handed forward again.
        for target in targets:
            self.link(target)
        self.assertEqual(migration.migrate(self.home, self.allowlist, rollback_files=files)["moved"], 0)
        self.assertEqual(self.migrate()["moved"], 3)
        self.assertTrue((Path(forward["backup"]) / "files" / targets[0]).is_symlink())

    def test_rollback_only_handles_allowlisted_paths_in_the_selected_generation(self):
        self.manifest(["managed", "not-in-old-generation"])
        files = self.old_files(["managed", "not-allowlisted"])
        for relative in ["managed", "not-in-old-generation", "not-allowlisted"]:
            (self.home / relative).write_text("current contents")
        result = migration.migrate(self.home, self.allowlist, rollback_files=files)
        self.assertEqual(result["moved"], 1)
        for relative in ["not-in-old-generation", "not-allowlisted"]:
            self.assertEqual((self.home / relative).read_text(), "current contents")

    def test_rollback_rejects_directory_and_symlink_parent_before_any_move(self):
        self.manifest(["first", "z/file"])
        files = self.old_files(["first", "z/file"])
        (self.home / "first").write_text("preserve")
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "file").write_text("outside")
        (self.home / "z").symlink_to(outside)
        with self.assertRaises(ValueError):
            migration.migrate(self.home, self.allowlist, rollback_files=files)
        self.assertEqual((self.home / "first").read_text(), "preserve")
        self.assertEqual((outside / "file").read_text(), "outside")
        (self.home / "z").unlink()
        (self.home / "z/file").mkdir(parents=True)
        with self.assertRaises(ValueError):
            migration.migrate(self.home, self.allowlist, rollback_files=files)
        self.assertFalse(self.state.exists())

    def test_rollback_rejects_collected_source_and_user_edits_during_preparation(self):
        self.manifest(["config"])
        files = self.old_files(["config"])
        current = self.home / "config"
        current.write_text("current")
        (files / "config").unlink()
        (files / "config").symlink_to(self.root / "missing")
        with self.assertRaises(ValueError):
            migration.migrate(self.home, self.allowlist, rollback_files=files)
        self.assertFalse(self.state.exists())
        (files / "config").unlink()
        (files / "config").write_text("old config")
        original_write = migration.write_audit

        def concurrent_edit(run_fd, audit):
            original_write(run_fd, audit)
            current.write_text("edited during preparation")

        with patch.object(migration, "write_audit", side_effect=concurrent_edit):
            with self.assertRaises(ValueError):
                migration.migrate(self.home, self.allowlist, rollback_files=files)
        self.assertEqual(current.read_text(), "edited during preparation")

    def test_rollback_leaves_already_owned_link_in_symlinked_theme_directory(self):
        relative = ".config/gtk-4.0/settings.ini"
        self.manifest([relative])
        files = self.old_files([relative])
        theme = self.root / "theme"
        theme.mkdir()
        (theme / "settings.ini").symlink_to(HM_ROOT + relative)
        (self.home / ".config").mkdir()
        (self.home / ".config/gtk-4.0").symlink_to(theme)
        result = migration.migrate(self.home, self.allowlist, rollback_files=files)
        self.assertEqual(result["moved"], 0)
        self.assertEqual(os.readlink(theme / "settings.ini"), HM_ROOT + relative)
        self.assertFalse(self.state.exists())

    def test_reads_old_unit_without_executing_commands(self):
        generation = "/nix/store/" + "a" * 32 + "-home-manager-generation"
        unit = f"[Service]\nExecStart=/nix/store/setup-env {generation}\nUser=present\n"
        self.assertEqual(migration.home_manager_generation(unit), Path(generation))
        for bad in ["", "ExecStart=/bin/sh -c 'anything'", unit + "ExecStart=/bin/false\n"]:
            with self.assertRaises(ValueError):
                migration.home_manager_generation(bad)

    @unittest.skipUnless(os.environ.get("HJEM_BIN"), "requires the built Hjem CLI")
    def test_actual_hjem_activation_after_rollback_and_repeat_migration(self):
        relative = ".config/example.conf"
        self.manifest([relative])
        self.link(relative)
        self.migrate()
        source = self.root / "hjem-source"
        source.write_text("new config")
        manifest = self.root / "hjem.json"
        manifest.write_text(json.dumps({"version": 3, "files": [{
            "type": "symlink", "source": str(source), "target": str(self.home / relative),
        }]}))
        state = self.root / "hjem-state.json"

        def activate():
            subprocess.run([os.environ["HJEM_BIN"], "internal", "activate", "--manifest", str(manifest),
                            "--state", str(state), "--json"], check=True, capture_output=True)
            self.assertEqual((self.home / relative).read_text(), "new config")

        activate()
        files = self.old_files([relative])
        migration.migrate(self.home, self.allowlist, rollback_files=files)
        self.link(relative)
        self.migrate()
        activate()  # Same Hjem state, but the old activation replaced the files.
        activate()  # Idempotent after the full round trip.

    def test_moves_dangling_links_and_keeps_auditable_original_targets(self):
        targets = [".config/niri/config.kdl", ".config/fastfetch/logo", ".zshrc"]
        self.manifest(targets)
        links = {target: self.link(target) for target in targets}
        self.assertTrue(all(not link.exists() and link.is_symlink() for link in links.values()))
        result = self.migrate()
        self.assertEqual(result["moved"], 3)
        backup = Path(result["backup"])
        self.assertEqual(backup.parent, self.state)
        audit = json.loads((backup / "manifest.json").read_text())
        self.assertEqual(audit["allowlist"]["host"], "test")
        self.assertEqual(audit["home"], str(self.home))
        self.assertEqual(len(audit["allowlist"]["sha256"]), 64)
        self.assertIn("completedAt", audit)
        for entry in audit["entries"]:
            self.assertEqual(entry["status"], "moved")
            self.assertEqual(entry["originalTarget"], HM_ROOT + entry["path"])
            saved = backup / entry["backupPath"]
            self.assertTrue(saved.is_symlink())
            self.assertEqual(os.readlink(saved), entry["originalTarget"])
            self.assertFalse(os.path.lexists(self.home / entry["path"]))
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
        self.assertEqual((backup / "manifest.json").stat().st_mode & 0o777, 0o600)
        # The containing config directories remain in place.
        self.assertTrue((self.home / ".config/niri").is_dir())

    def test_preserves_user_files_directories_and_other_links(self):
        ordinary = self.home / "ordinary"
        ordinary.write_text("user settings")
        directory = self.home / "directory"
        directory.mkdir()
        (directory / "data").write_bytes(b"keep")
        foreign_targets = {
            "other-store-link": "/nix/store/" + "b" * 32 + "-kitty.conf",
            "different-hm-path": HM_ROOT + "somewhere-else",
            "relative-hm-link": "../nix/store/" + "a" * 32 + "-home-manager-files/relative-hm-link",
            "not-nix-hash": "/nix/store/not-a-hash-home-manager-files/not-nix-hash",
            "outside": str(self.root / "user-data"),
            "normalized-suffix": HM_ROOT + "other/../normalized-suffix",
            "extra-suffix": HM_ROOT + "extra-suffix/",
        }
        for relative, target in foreign_targets.items():
            self.link(relative, target)
        unlisted = self.link("unlisted")
        self.manifest(["ordinary", "directory", *foreign_targets])
        self.assertEqual(self.migrate(), {"moved": 0, "backup": None})
        self.assertEqual(ordinary.read_text(), "user settings")
        self.assertEqual((directory / "data").read_bytes(), b"keep")
        for relative, target in foreign_targets.items():
            self.assertEqual(os.readlink(self.home / relative), target)
        self.assertEqual(os.readlink(unlisted), HM_ROOT + "unlisted")
        self.assertFalse(self.state.exists())

    def test_repeated_run_is_empty_and_rollback_then_forward_is_supported(self):
        self.manifest([".zshrc"])
        self.link(".zshrc")
        first = self.migrate()
        saved = Path(first["backup"]) / "files/.zshrc"
        before = set(self.state.iterdir())
        self.assertEqual(self.migrate(), {"moved": 0, "backup": None})
        self.assertEqual(set(self.state.iterdir()), before)
        # A NixOS/HM rollback recreates the old link; a later migration backs it up again.
        self.link(".zshrc", os.readlink(saved))
        second = self.migrate()
        self.assertEqual(second["moved"], 1)
        self.assertNotEqual(first["backup"], second["backup"])
        self.assertTrue(saved.is_symlink())
        self.assertTrue((Path(second["backup"]) / "files/.zshrc").is_symlink())

    def test_user_replacement_after_migration_is_preserved(self):
        self.manifest([".zshrc"])
        self.link(".zshrc")
        first = self.migrate()
        (self.home / ".zshrc").write_text("new user config")
        self.assertEqual(self.migrate()["moved"], 0)
        self.assertEqual((self.home / ".zshrc").read_text(), "new user config")
        self.assertTrue((Path(first["backup"]) / "files/.zshrc").is_symlink())

    def test_user_change_after_collection_is_preserved(self):
        self.manifest([".zshrc"])
        link = self.link(".zshrc")
        original_write = migration.write_audit
        changed = False

        def replace_after_audit(run_fd, audit):
            nonlocal changed
            original_write(run_fd, audit)
            if not changed:
                changed = True
                link.unlink()
                link.write_text("edited during migration")

        with patch.object(migration, "write_audit", side_effect=replace_after_audit):
            result = self.migrate()
        self.assertEqual(result["moved"], 0)
        self.assertEqual(link.read_text(), "edited during migration")
        audit = json.loads((Path(result["backup"]) / "manifest.json").read_text())
        self.assertEqual(audit["entries"][0]["status"], "changed; preserved")

    def test_manifest_traversal_is_rejected_before_any_move(self):
        good = self.link("good")
        for target in ["../escape", "/tmp/escape", "a/../../escape", "a//b", "a/./b", "", ".", "a/", "a\0b", ".local/state/home-manager-migration/run/files/x"]:
            with self.subTest(target=target):
                self.manifest(["good", target])
                with self.assertRaises(ValueError):
                    self.migrate()
                self.assertEqual(os.readlink(good), HM_ROOT + "good")
        self.assertFalse(self.state.exists())

    def test_symlink_parent_outside_home_is_never_followed(self):
        outside = self.root / "outside"
        outside.mkdir()
        link = outside / "config"
        link.symlink_to(HM_ROOT + ".config/config")
        (self.home / ".config").symlink_to(outside, target_is_directory=True)
        self.manifest([".config/config"])
        self.assertEqual(self.migrate()["moved"], 0)
        self.assertEqual(os.readlink(link), HM_ROOT + ".config/config")
        self.assertFalse(self.state.exists())

    def test_symlink_parent_inside_home_is_also_left_alone(self):
        real = self.home / "real"
        real.mkdir()
        (real / "file").symlink_to(HM_ROOT + "alias/file")
        (self.home / "alias").symlink_to(real, target_is_directory=True)
        self.manifest(["alias/file"])
        self.assertEqual(self.migrate()["moved"], 0)
        self.assertEqual(os.readlink(real / "file"), HM_ROOT + "alias/file")

    def test_missing_or_broken_parent_is_left_alone(self):
        (self.home / "broken").symlink_to(self.root / "missing")
        self.manifest(["missing/file", "broken/file"])
        self.assertEqual(self.migrate()["moved"], 0)
        self.assertTrue((self.home / "broken").is_symlink())
        self.assertFalse(self.state.exists())

    def test_backup_parent_symlink_is_refused_before_moving(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.home / ".local").symlink_to(outside, target_is_directory=True)
        link = self.link(".zshrc")
        self.manifest([".zshrc"])
        with self.assertRaises(OSError):
            self.migrate()
        self.assertEqual(os.readlink(link), HM_ROOT + ".zshrc")
        self.assertEqual(list(outside.iterdir()), [])

    def test_manifest_must_have_valid_schema_and_unique_targets(self):
        for data in [[], {"version": 2, "targets": []}, {"version": 1, "targets": "x"}, {"version": 1, "targets": ["x", "x"]}, {"version": 1, "targets": [42]}]:
            with self.subTest(data=data):
                self.allowlist.write_text(json.dumps(data))
                with self.assertRaises(ValueError):
                    self.migrate()

    def test_cli_requires_explicit_home_and_manifest_and_uses_only_that_home(self):
        self.manifest([".zshrc"])
        self.link(".zshrc")
        result = subprocess.run(
            [sys.executable, str(MODULE), "--home", str(self.home), "--manifest", str(self.allowlist)],
            text=True, capture_output=True, check=True,
        )
        self.assertEqual(json.loads(result.stdout)["moved"], 1)
        missing = subprocess.run([sys.executable, str(MODULE)], text=True, capture_output=True)
        self.assertNotEqual(missing.returncode, 0)


if __name__ == "__main__":
    unittest.main()
