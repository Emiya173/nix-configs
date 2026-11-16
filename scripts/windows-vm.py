"""Manage the declared win11 guest and offline, self-contained recovery bundles."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import sys
import tempfile
import uuid
from xml.etree import ElementTree as ET


def canonical(xml):
    return ET.canonicalize(xml, strip_text=True)


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".pending-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def lookup(connection, api, name):
    try:
        return connection.lookupByName(name)
    except api.libvirtError as error:
        if error.get_error_code() != api.VIR_ERR_NO_DOMAIN:
            raise
        return None


def check_identity(domain, cfg):
    if not domain.isPersistent() or domain.UUIDString() != cfg["uuid"]:
        raise ValueError("Existing guest identity differs from Nix; refusing to replace it")
    xml = ET.fromstring(domain.XMLDesc(2))  # VIR_DOMAIN_XML_INACTIVE
    disks = xml.findall("./devices/disk[@device='disk']")
    if (len(disks) != 1 or disks[0].find("source") is None
            or disks[0].find("source").get("file") != cfg["disk"]
            or disks[0].find("driver") is None or disks[0].find("driver").get("type") != "qcow2"):
        raise ValueError("Existing disk layout differs from Nix; reconcile it before continuing")


def require_offline(domain, api):
    if domain is not None:
        if domain.state()[0] != api.VIR_DOMAIN_SHUTOFF or domain.hasManagedSaveImage(0):
            raise ValueError("Fully shut down Windows first; running, paused and saved guests are refused")


def set_qemu_owner(path, cfg):
    account = pwd.getpwnam(cfg["qemuUser"])
    os.chown(path, account.pw_uid, account.pw_gid)
    os.chmod(path, 0o600)


def ensure_disk(cfg, existing):
    disk = Path(cfg["disk"])
    if disk.exists():
        return
    if existing is not None or any(Path(cfg[key]).exists() for key in ("nvram", "tpm")):
        raise ValueError("System disk is missing but guest state exists; restore the disk instead of creating one")
    disk.parent.mkdir(parents=True, exist_ok=True)
    temporary = disk.with_name(f".{disk.name}.new-{uuid.uuid4().hex}")
    try:
        subprocess.run([cfg["qemuImg"], "create", "-f", "qcow2", "-o", "nocow=on",
                        str(temporary), f'{cfg["diskGiB"]}G'], check=True)
        set_qemu_owner(temporary, cfg)
        # No-clobber publication: never replace an existing Windows disk.
        os.link(temporary, disk)
    finally:
        temporary.unlink(missing_ok=True)


def desired_xml(cfg):
    root = ET.parse(cfg["domainXML"]).getroot()
    for disk in root.findall("./devices/disk[@device='cdrom']"):
        source = disk.find("source")
        if source is not None and not Path(source.get("file")).is_file():
            disk.remove(source)
    return ET.tostring(root, encoding="unicode")


def ensure_network(connection, api, cfg):
    root = ET.parse(cfg["networkXML"]).getroot()
    try:
        network = connection.networkLookupByName(cfg["network"])
    except api.libvirtError as error:
        if error.get_error_code() != api.VIR_ERR_NO_NETWORK:
            raise
        network = None
    if network is not None:
        # A fresh libvirt installation may already have generated this network.
        root.find("uuid").text = network.UUIDString()
    xml = ET.tostring(root, encoding="unicode")
    if network is None or canonical(network.XMLDesc(1)) != canonical(xml):
        network = connection.networkDefineXML(xml)
    # virt-manager starts domains directly, bypassing our `start` command.
    # Keep their network ready while leaving the Windows domain manual.
    if not network.autostart():
        network.setAutostart(1)
    if not network.isActive():
        network.create()
    return network


def require_complete_restore(cfg):
    receipt = Path(cfg["state"]) / "restore-in-progress.json"
    if receipt.exists():
        raise ValueError(f"An interrupted restore needs recovery; inspect {receipt} before starting Windows")


def reconcile(connection, api, cfg, during_restore=False):
    if not during_restore:
        require_complete_restore(cfg)
    domain = lookup(connection, api, cfg["name"])
    if domain is not None:
        check_identity(domain, cfg)
    ensure_disk(cfg, domain)
    ensure_network(connection, api, cfg)
    xml = desired_xml(cfg)
    digest = hashlib.sha256(xml.encode()).hexdigest()
    state_file = Path(cfg["state"]) / "definition.json"
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    current = canonical(domain.XMLDesc(2)) if domain is not None else None
    # Compare libvirt's own normalized definition to avoid a watcher feedback loop.
    if state.get("desired") != digest or state.get("applied") != current:
        domain = connection.defineXMLFlags(xml, api.VIR_DOMAIN_DEFINE_VALIDATE)
        atomic_json(state_file, {"desired": digest, "applied": canonical(domain.XMLDesc(2))})
        print("win11 definition applied; running guests use it after a full shutdown and start")
    if domain.autostart():
        domain.setAutostart(0)
    return domain


def inventory(directory):
    records = {}
    for path in sorted(Path(directory).rglob("*")):
        relative = path.relative_to(directory).as_posix()
        if relative == "manifest.json":
            continue
        if path.is_symlink():
            records[relative] = {"link": os.readlink(path)}
        elif path.is_file():
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
                    digest.update(chunk)
            records[relative] = {"sha256": digest.hexdigest(), "size": path.stat().st_size}
        elif path.is_dir():
            records[relative] = {"directory": True}
        else:
            raise ValueError(f"Unsupported special file in backup: {relative}")
    return records


def copy(cfg, source, destination):
    subprocess.run([cfg["copy"], "-a", "--reflink=never", "--sparse=always", "--",
                    str(source), str(destination)], check=True)


def backup(connection, api, cfg, destination):
    require_complete_restore(cfg)
    domain = lookup(connection, api, cfg["name"])
    if domain is None:
        raise ValueError("win11 is not defined")
    check_identity(domain, cfg)
    require_offline(domain, api)
    destination = Path(destination).absolute()
    if destination.exists():
        raise ValueError("Backup destination already exists; choose a new directory")
    for key in ("tpm", "share", "state"):
        if destination.resolve().is_relative_to(Path(cfg[key]).resolve()):
            raise ValueError("Backup destination cannot be inside the data being backed up")
    for key in ("disk", "nvram", "tpm", "share"):
        if not Path(cfg[key]).exists():
            raise ValueError(f"Required {key} state is missing: {cfg[key]}")
    xml = domain.XMLDesc(api.VIR_DOMAIN_XML_INACTIVE | api.VIR_DOMAIN_XML_SECURE)
    if ET.fromstring(xml).find("./devices/tpm/backend/encryption") is not None:
        raise ValueError("Encrypted TPM state requires a separate secret backup and is not supported")
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{destination.name}.pending-", dir=destination.parent))
    try:
        # Conversion flattens external backing chains into one independent disk.
        subprocess.run([cfg["qemuImg"], "convert", "-p", "-f", "qcow2", "-O", "qcow2",
                        cfg["disk"], str(staging / "disk.qcow2")], check=True)
        for key, filename in (("nvram", "nvram.fd"), ("tpm", "tpm"), ("share", "share")):
            copy(cfg, cfg[key], staging / filename)
        (staging / "domain.xml").write_text(xml)
        require_offline(domain, api)
        atomic_json(staging / "manifest.json", {
            "version": 1, "name": cfg["name"], "uuid": cfg["uuid"],
            "created": datetime.now(timezone.utc).isoformat(), "files": inventory(staging),
        })
        if destination.exists():
            raise ValueError("Backup destination appeared during backup")
        staging.rename(destination)
    except BaseException:
        shutil.rmtree(staging)
        raise
    print(f"Recovery bundle: {destination}")


def verify_bundle(cfg, source):
    source = Path(source).absolute()
    if source.is_symlink():
        raise ValueError("Recovery bundle must be a real directory")
    manifest = json.loads((source / "manifest.json").read_text())
    if (manifest.get("version"), manifest.get("name"), manifest.get("uuid")) != (
            1, cfg["name"], cfg["uuid"]):
        raise ValueError("Recovery bundle identity or version differs from Nix")
    for filename in ("disk.qcow2", "nvram.fd", "tpm", "share", "domain.xml"):
        path = source / filename
        expected_type = path.is_dir() if filename in ("tpm", "share") else path.is_file()
        if path.is_symlink() or not expected_type:
            raise ValueError(f"Invalid or missing recovery artifact: {filename}")
    if inventory(source) != manifest.get("files"):
        raise ValueError("Recovery bundle checksum or file inventory mismatch")
    image = json.loads(subprocess.check_output(
        [cfg["qemuImg"], "info", "-f", "qcow2", "--output=json", str(source / "disk.qcow2")]))
    if (image.get("backing-filename") or image.get("data-file")
            or image.get("format-specific", {}).get("data", {}).get("data-file")):
        raise ValueError("Recovery disk must not depend on external image files")
    subprocess.run([cfg["qemuImg"], "check", "-f", "qcow2", str(source / "disk.qcow2")], check=True)
    return source


def remove_copy(path):
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink(missing_ok=True)


def restore(connection, api, cfg, source, apply=False):
    require_complete_restore(cfg)
    source = verify_bundle(cfg, source)
    domain = lookup(connection, api, cfg["name"])
    if domain is not None:
        check_identity(domain, cfg)
        if domain.snapshotNum(0):
            raise ValueError("Existing libvirt snapshot metadata must be handled before restoring")
    require_offline(domain, api)
    entries = [(source / filename, Path(cfg[key])) for key, filename in (
        ("disk", "disk.qcow2"), ("nvram", "nvram.fd"), ("tpm", "tpm"), ("share", "share"))]
    for origin, target in entries:
        print(f"Restore {origin.name} -> {target}; existing data will be retained beside it")
    if not apply:
        print("Preview only. Add --apply to restore; keep Windows shut down until it completes.")
        return
    suffix = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    staged, journal = [], []
    original_xml = domain.XMLDesc(3) if domain is not None else None
    receipt = Path(cfg["state"]) / "restore-in-progress.json"
    try:
        # Prepare all data before moving any existing files; no tar extraction.
        for origin, target in entries:
            target.parent.mkdir(parents=True, exist_ok=True)
            pending = target.with_name(f".{target.name}.restore-{suffix}")
            staged.append(pending)
            copy(cfg, origin, pending)
            if target == Path(cfg["disk"]) or target == Path(cfg["nvram"]):
                set_qemu_owner(pending, cfg)
        require_offline(domain, api)
        plan = [{"target": str(target),
                 "retained": str(target.with_name(f"{target.name}.before-restore-{suffix}")),
                 "pending": str(pending), "existed": target.exists() or target.is_symlink()}
                for (_, target), pending in zip(entries, staged)]
        atomic_json(receipt, {"source": str(source), "entries": plan, "original_xml": original_xml})
        for (_, target), pending in zip(entries, staged):
            retained = target.with_name(f"{target.name}.before-restore-{suffix}")
            existed = target.exists() or target.is_symlink()
            journal.append((target, retained, existed))
            if existed:
                target.rename(retained)
            pending.rename(target)
        reconcile(connection, api, cfg, during_restore=True)
        atomic_json(Path(cfg["state"]) / "last-restore.json", {
            "source": str(source),
            "retained": {str(target): str(retained) for target, retained, existed in journal if existed},
        })
        receipt.unlink()
    except BaseException:
        for target, retained, existed in reversed(journal):
            # If moving the original failed, it is still in place.
            if existed and not retained.exists() and not retained.is_symlink():
                continue
            remove_copy(target)
            if existed:
                retained.rename(target)
        if original_xml is not None:
            connection.defineXMLFlags(original_xml, api.VIR_DOMAIN_DEFINE_VALIDATE)
        receipt.unlink(missing_ok=True)
        raise
    finally:
        for pending in staged:
            remove_copy(pending)
    print("Restore complete. Previous data was retained; Windows has not been started.")


@contextmanager
def exclusive(cfg):
    with open(cfg["lock"], "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def main():
    import libvirt

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("reconcile")
    commands.add_parser("start")
    commands.add_parser("status")
    commands.add_parser("backup").add_argument("destination")
    restore_parser = commands.add_parser("restore")
    restore_parser.add_argument("source")
    restore_parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    cfg = json.loads(Path(args.config).read_text())
    libvirt.registerErrorHandler(lambda *_: None, None)
    connection = libvirt.open("qemu:///system")
    try:
        if args.command == "status":
            domain = lookup(connection, libvirt, cfg["name"])
            print(f'{cfg["name"]}: ' + (f"libvirt state {domain.state()[0]}" if domain else "not defined"))
            for key in ("disk", "nvram", "tpm", "share", "windowsISO", "virtioISO"):
                print(f'{key}: {cfg[key]} ({"present" if Path(cfg[key]).exists() else "missing"})')
            return
        if os.geteuid() != 0:
            raise ValueError("Run this operation with sudo")
        with exclusive(cfg):
            if args.command == "reconcile":
                reconcile(connection, libvirt, cfg)
            elif args.command == "start":
                domain = reconcile(connection, libvirt, cfg)
                network = connection.networkLookupByName(cfg["network"])
                if not network.isActive():
                    network.create()
                if not domain.isActive():
                    domain.create()
            elif args.command == "backup":
                backup(connection, libvirt, cfg, args.destination)
            elif args.command == "restore":
                restore(connection, libvirt, cfg, args.source, args.apply)
    except libvirt.libvirtError as error:
        raise ValueError(f"libvirt: {error}") from error
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
