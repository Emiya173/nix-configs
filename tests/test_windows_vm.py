"""Exercise VM lifecycle and recovery only with fake libvirt and /tmp disks."""

import importlib.util
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from xml.etree import ElementTree as ET


MODULE = Path(os.environ.get(
    "WINDOWS_VM_MODULE", Path(__file__).parents[1] / "scripts/windows-vm.py"))
spec = importlib.util.spec_from_file_location("windows_vm", MODULE)
vm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vm)
QEMU_IMG = os.environ.get("QEMU_IMG", shutil.which("qemu-img"))
COPY_PROGRAM = os.environ.get("COPY_PROGRAM", shutil.which("cp"))


class Missing(Exception):
    def get_error_code(self):
        return 42


API = SimpleNamespace(libvirtError=Missing, VIR_ERR_NO_DOMAIN=42, VIR_ERR_NO_NETWORK=42,
                      VIR_DOMAIN_SHUTOFF=5, VIR_DOMAIN_XML_INACTIVE=2,
                      VIR_DOMAIN_XML_SECURE=1, VIR_DOMAIN_DEFINE_VALIDATE=1)


class Domain:
    def __init__(self, xml):
        self.xml = xml
        self.active = False
        self.saved = False
        self.auto = True

    def isPersistent(self):
        return True

    def UUIDString(self):
        return ET.fromstring(self.xml).findtext("uuid")

    def XMLDesc(self, flags):
        return self.xml

    def state(self):
        return (1 if self.active else 5, 0)

    def hasManagedSaveImage(self, flags):
        return self.saved

    def snapshotNum(self, flags):
        return 0

    def autostart(self):
        return self.auto

    def setAutostart(self, auto):
        self.auto = bool(auto)


class Network:
    def __init__(self, xml):
        self.xml = xml
        self.auto = False
        self.active = False
        self.starts = 0

    def UUIDString(self):
        return ET.fromstring(self.xml).findtext("uuid")

    def XMLDesc(self, flags):
        return self.xml

    def autostart(self):
        return self.auto

    def setAutostart(self, auto):
        self.auto = bool(auto)

    def isActive(self):
        return self.active

    def create(self):
        if self.active:
            raise ValueError("network is already active")
        self.active = True
        self.starts += 1


class Connection:
    def __init__(self):
        self.domain = None
        self.network = None
        self.definitions = 0

    def lookupByName(self, name):
        if self.domain is None:
            raise Missing()
        return self.domain

    def defineXMLFlags(self, xml, flags):
        root = ET.fromstring(xml)
        # Simulate libvirt normalization that adds implicit attributes.
        root.find("./devices/disk/driver").set("name", "qemu")
        if self.domain is None:
            self.domain = Domain(ET.tostring(root, encoding="unicode"))
        else:
            self.domain.xml = ET.tostring(root, encoding="unicode")
        self.definitions += 1
        return self.domain

    def networkLookupByName(self, name):
        if self.network is None:
            raise Missing()
        return self.network

    def networkDefineXML(self, xml):
        self.network = Network(xml)
        return self.network


@unittest.skipUnless(QEMU_IMG and COPY_PROGRAM, "qemu-img and cp are required")
class WindowsVmTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="windows-vm-test-", dir="/tmp")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.cfg = {
            "name": "win11", "uuid": "c57f5e4c-95fe-48e0-adf6-3db16ef61b9a", "diskGiB": 1,
            "qemuImg": QEMU_IMG, "copy": COPY_PROGRAM, "network": "default",
            "qemuUser": pwd.getpwuid(os.geteuid()).pw_name,
        }
        for key in ("disk", "nvram", "tpm", "share", "state", "domainXML", "networkXML"):
            self.cfg[key] = str(self.root / key)
        Path(self.cfg["domainXML"]).write_text(f'''<domain type="kvm">
          <name>win11</name><uuid>{self.cfg["uuid"]}</uuid><memory unit="MiB">8192</memory>
          <devices><disk type="file" device="disk"><driver type="qcow2"/>
          <source file="{self.cfg["disk"]}"/><target dev="sda" bus="sata"/></disk>
          <disk type="file" device="cdrom"><source file="{self.root}/missing.iso"/>
          <target dev="sdb" bus="sata"/></disk></devices></domain>''')
        Path(self.cfg["networkXML"]).write_text('''<network><name>default</name>
          <uuid>ab517a13-e53e-4179-bb24-ea04be42bee5</uuid><forward mode="nat"/></network>''')
        self.connection = Connection()

    def run_qemu(self, *arguments):
        subprocess.run([QEMU_IMG, *arguments], check=True, stdout=subprocess.DEVNULL)

    def installed_guest(self):
        vm.reconcile(self.connection, API, self.cfg)
        Path(self.cfg["nvram"]).write_bytes(b"UEFI variables")
        Path(self.cfg["tpm"]).mkdir()
        (Path(self.cfg["tpm"]) / "tpm2-state").write_bytes(b"TPM keys")
        Path(self.cfg["share"]).mkdir()
        (Path(self.cfg["share"]) / "document.txt").write_text("Office document")

    def bundle(self):
        self.installed_guest()
        destination = self.root / "backup"
        vm.backup(self.connection, API, self.cfg, destination)
        return destination

    def test_new_host_initializes_disk_and_definition_without_starting_guest(self):
        domain = vm.reconcile(self.connection, API, self.cfg)
        self.assertTrue(Path(self.cfg["disk"]).is_file())
        self.assertFalse(domain.active)
        self.assertFalse(domain.auto)
        self.assertIsNotNone(self.connection.network)
        self.assertTrue(self.connection.network.auto)
        self.assertTrue(self.connection.network.active)
        cdrom = ET.fromstring(domain.xml).find("./devices/disk[@device='cdrom']")
        self.assertIsNone(cdrom.find("source"))

    def test_reconcile_recovers_stopped_network_without_starting_windows(self):
        vm.reconcile(self.connection, API, self.cfg)
        network = self.connection.network
        network.active = False
        network.auto = False
        vm.reconcile(self.connection, API, self.cfg)
        self.assertTrue(network.auto)
        self.assertTrue(network.active)
        self.assertEqual(network.starts, 2)
        self.assertFalse(self.connection.domain.active)
        self.assertFalse(self.connection.domain.auto)
        vm.reconcile(self.connection, API, self.cfg)
        self.assertEqual(network.starts, 2)

    def test_reconcile_is_idempotent_and_does_not_overwrite_existing_disk(self):
        vm.reconcile(self.connection, API, self.cfg)
        before = Path(self.cfg["disk"]).read_bytes()
        vm.reconcile(self.connection, API, self.cfg)
        self.assertEqual(self.connection.definitions, 1)
        self.assertEqual(before, Path(self.cfg["disk"]).read_bytes())
        self.connection.domain.xml = self.connection.domain.xml.replace("8192", "4096")
        vm.reconcile(self.connection, API, self.cfg)
        self.assertEqual(self.connection.definitions, 2)

    def test_missing_disk_with_existing_state_is_not_recreated(self):
        Path(self.cfg["nvram"]).write_text("keep")
        with self.assertRaisesRegex(ValueError, "disk is missing"):
            vm.reconcile(self.connection, API, self.cfg)
        self.assertFalse(Path(self.cfg["disk"]).exists())

    def test_interrupted_restore_blocks_reconciliation_and_disk_creation(self):
        Path(self.cfg["state"]).mkdir()
        (Path(self.cfg["state"]) / "restore-in-progress.json").write_text('{}')
        with self.assertRaisesRegex(ValueError, "interrupted restore"):
            vm.reconcile(self.connection, API, self.cfg)
        self.assertFalse(Path(self.cfg["disk"]).exists())

    def test_different_guest_identity_is_refused(self):
        vm.reconcile(self.connection, API, self.cfg)
        self.connection.domain.xml = self.connection.domain.xml.replace(self.cfg["uuid"], "other-uuid")
        with self.assertRaisesRegex(ValueError, "identity differs"):
            vm.reconcile(self.connection, API, self.cfg)

    def test_backup_refuses_running_and_saved_guests(self):
        self.installed_guest()
        for active, saved in ((True, False), (False, True)):
            self.connection.domain.active, self.connection.domain.saved = active, saved
            with self.assertRaisesRegex(ValueError, "Fully shut down"):
                vm.backup(self.connection, API, self.cfg, self.root / "backup")
        self.assertFalse((self.root / "backup").exists())

    def test_backup_flattens_external_disk_chain(self):
        self.installed_guest()
        disk = Path(self.cfg["disk"])
        base = self.root / "base.qcow2"
        disk.rename(base)
        self.run_qemu("create", "-f", "qcow2", "-F", "qcow2", "-b", str(base), str(disk))
        destination = self.root / "backup"
        vm.backup(self.connection, API, self.cfg, destination)
        base.unlink()
        vm.verify_bundle(self.cfg, destination)

    def test_restore_preview_changes_nothing(self):
        source = self.bundle()
        Path(self.cfg["nvram"]).write_text("current variables")
        vm.restore(self.connection, API, self.cfg, source)
        self.assertEqual(Path(self.cfg["nvram"]).read_text(), "current variables")
        self.assertFalse(list(self.root.glob("*.before-restore-*")))

    def test_restore_retains_old_state_and_restores_all_artifacts(self):
        source = self.bundle()
        Path(self.cfg["nvram"]).write_text("old variables")
        vm.restore(self.connection, API, self.cfg, source, apply=True)
        self.assertEqual(Path(self.cfg["nvram"]).read_bytes(), b"UEFI variables")
        report = json.loads((Path(self.cfg["state"]) / "last-restore.json").read_text())
        self.assertEqual(len(report["retained"]), 4)
        self.assertEqual(Path(report["retained"][self.cfg["nvram"]]).read_text(), "old variables")
        self.assertFalse(self.connection.domain.active)

    def test_restore_on_new_host_replaces_only_the_generated_blank_disk(self):
        source = self.bundle()
        new_root = self.root / "new-host"
        new_root.mkdir()
        cfg = dict(self.cfg)
        for key in ("disk", "nvram", "tpm", "share", "state", "domainXML"):
            cfg[key] = str(new_root / key)
        Path(cfg["domainXML"]).write_text(
            Path(self.cfg["domainXML"]).read_text().replace(self.cfg["disk"], cfg["disk"]))
        connection = Connection()
        vm.reconcile(connection, API, cfg)
        vm.restore(connection, API, cfg, source, apply=True)
        self.assertEqual(Path(cfg["nvram"]).read_bytes(), b"UEFI variables")
        self.assertEqual((Path(cfg["tpm"]) / "tpm2-state").read_bytes(), b"TPM keys")
        self.assertEqual((Path(cfg["share"]) / "document.txt").read_text(), "Office document")
        report = json.loads((Path(cfg["state"]) / "last-restore.json").read_text())
        self.assertEqual(set(report["retained"]), {cfg["disk"]})

    def test_restore_refuses_running_target_without_changing_its_files(self):
        source = self.bundle()
        self.connection.domain.active = True
        with self.assertRaisesRegex(ValueError, "Fully shut down"):
            vm.restore(self.connection, API, self.cfg, source, apply=True)
        self.assertFalse(list(self.root.glob("*.before-restore-*")))

    def test_failed_staging_does_not_move_existing_data(self):
        source = self.bundle()
        with patch.object(vm, "copy", side_effect=OSError("disk full")):
            with self.assertRaisesRegex(OSError, "disk full"):
                vm.restore(self.connection, API, self.cfg, source, apply=True)
        self.assertEqual(Path(self.cfg["nvram"]).read_bytes(), b"UEFI variables")
        self.assertFalse(list(self.root.glob("*.before-restore-*")))

    def test_corrupt_backup_is_refused_before_touching_targets(self):
        source = self.bundle()
        (source / "nvram.fd").write_text("corrupt")
        with self.assertRaisesRegex(ValueError, "checksum"):
            vm.restore(self.connection, API, self.cfg, source, apply=True)
        self.assertEqual(Path(self.cfg["nvram"]).read_bytes(), b"UEFI variables")

    def test_restore_rolls_back_files_when_domain_definition_fails(self):
        source = self.bundle()
        Path(self.cfg["nvram"]).write_text("old variables")
        with patch.object(vm, "reconcile", side_effect=ValueError("definition failed")):
            with self.assertRaisesRegex(ValueError, "definition failed"):
                vm.restore(self.connection, API, self.cfg, source, apply=True)
        self.assertEqual(Path(self.cfg["nvram"]).read_text(), "old variables")
        self.assertFalse(list(self.root.glob("*.before-restore-*")))


if __name__ == "__main__":
    unittest.main()
