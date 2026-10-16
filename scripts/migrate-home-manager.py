#!/usr/bin/env python3
"""Move allowlisted Home Manager links aside without following user symlinks.

The manifest is a version-1 object with a host name and relative ``targets``.
Only direct links to the matching path in a *-home-manager-files store output
are eligible, including dangling links. Run as the owner of the chosen home.
Backups keep the original links under files/; manifest.json records each move.
With --rollback-system, preview the non-HM files that obstruct that generation.
--apply preserves those files before the caller activates the old system.
"""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import stat
import sys
import uuid


BACKUP_PARTS = (".local", "state", "home-manager-migration")
DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
HM_LINK = re.compile(r"/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-home-manager-files/(.+)\Z")
SKIPPABLE_PARENT_ERRORS = {errno.ENOENT, errno.ENOTDIR, errno.ELOOP}


def relative_parts(target):
    """Reject ambiguous, absolute, escaping, and backup-internal paths."""
    if not isinstance(target, str) or "\0" in target:
        raise ValueError("manifest targets must be relative path strings")
    parts = tuple(target.split("/"))
    if any(part in ("", ".", "..") for part in parts):
        raise ValueError(f"unsafe manifest target: {target!r}")
    if parts[:len(BACKUP_PARTS)] == BACKUP_PARTS:
        raise ValueError("the migration backup directory cannot be a target")
    return parts


def load_manifest(path):
    raw = Path(path).read_bytes()
    data = json.loads(raw)
    if not isinstance(data, dict) or data.get("version") != 1:
        raise ValueError("expected a version-1 allowlist manifest")
    targets = data.get("targets")
    if not isinstance(targets, list):
        raise ValueError("manifest targets must be a list")
    for target in targets:
        relative_parts(target)
    if len(set(targets)) != len(targets):
        raise ValueError("manifest contains duplicate targets")
    return sorted(targets), {
        "host": data.get("host"),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "path": str(Path(path).absolute()),
    }


@contextmanager
def directory_fd(root_fd, parts, *, create=False):
    """Walk real directories only, anchored to an already-open directory."""
    fd = os.dup(root_fd)
    try:
        for part in parts:
            if create:
                try:
                    os.mkdir(part, mode=0o700, dir_fd=fd)
                except FileExistsError:
                    pass
            next_fd = os.open(part, DIRECTORY_FLAGS, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        yield fd
    finally:
        os.close(fd)


def matching_link(parent_fd, name, relative):
    try:
        info = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        if not stat.S_ISLNK(info.st_mode):
            return None
        target = os.readlink(name, dir_fd=parent_fd)
    except FileNotFoundError:
        return None
    match = HM_LINK.fullmatch(target)
    if match is None or match.group(1) != relative:
        return None
    return {"target": target, "device": info.st_dev, "inode": info.st_ino}


def rollback_candidate(parent_fd, name, relative):
    """Preserve every non-HM file that the old generation needs to replace."""
    if matching_link(parent_fd, name, relative) is not None:
        return None
    try:
        info = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    if not (stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode)):
        raise ValueError(f"rollback target is a directory or special file: {relative}")
    return {
        "target": os.readlink(name, dir_fd=parent_fd) if stat.S_ISLNK(info.st_mode) else None,
        "device": info.st_dev,
        "inode": info.st_ino,
        "size": info.st_size,
        "mtime": info.st_mtime_ns,
    }


def candidates(home_fd, targets, rollback_files=None):
    result = []
    for relative in targets:
        parts = relative_parts(relative)
        if rollback_files is not None:
            source = rollback_files / relative
            if not os.path.lexists(source):
                continue  # This older generation did not manage this path.
            if source.is_dir() and not source.is_symlink():
                continue  # Container directory, not a managed file/link.
            if not source.exists():
                raise ValueError(f"old generation has a dangling source: {relative}")
        try:
            with directory_fd(home_fd, parts[:-1]) as parent_fd:
                inspect = matching_link if rollback_files is None else rollback_candidate
                found = inspect(parent_fd, parts[-1], relative)
                if found is not None:
                    result.append((relative, found))
        except OSError as error:
            if rollback_files is not None and error.errno in (errno.ENOTDIR, errno.ELOOP):
                # A legacy theme directory may itself be a symlink. Reading
                # the final link is safe if HM already owns it: no move is
                # needed, and we never open that external directory for writes.
                try:
                    target = os.readlink(relative, dir_fd=home_fd)
                except OSError:
                    target = ""
                match = HM_LINK.fullmatch(target)
                if match is not None and match.group(1) == relative:
                    continue
                raise ValueError(f"rollback target has a symlink or non-directory parent: {relative}") from error
            if error.errno not in SKIPPABLE_PARENT_ERRORS:
                raise
    return result


def write_audit(run_fd, audit):
    fd = os.open(
        "manifest.json.new",
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
        0o600,
        dir_fd=run_fd,
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(audit, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.rename("manifest.json.new", "manifest.json", src_dir_fd=run_fd, dst_dir_fd=run_fd)
        os.fsync(run_fd)
    except BaseException:
        # The previous audit remains intact if publishing this update fails.
        try:
            os.unlink("manifest.json.new", dir_fd=run_fd)
        except FileNotFoundError:
            pass
        raise


def migrate(home, manifest, *, rollback_files=None, apply=True):
    targets, source = load_manifest(manifest)
    home = Path(home)
    if not home.is_absolute():
        raise ValueError("--home must be an absolute path")
    home_fd = os.open(home, DIRECTORY_FLAGS)
    try:
        selected = candidates(home_fd, targets, rollback_files)
        if not apply:
            return {"conflicts": [relative for relative, _ in selected], "moved": 0, "backup": None}
        if not selected:
            return {"moved": 0, "backup": None}
        # No state is created for a home with no eligible links. Refuse a
        # symlink anywhere in the backup path before moving any source link.
        with directory_fd(home_fd, BACKUP_PARTS, create=True) as backup_fd:
            lock_fd = os.open(
                ".lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC,
                0o600, dir_fd=backup_fd,
            )
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_EX)
                selected = candidates(home_fd, targets, rollback_files)
                if not selected:
                    return {"moved": 0, "backup": None}
                started = datetime.now(timezone.utc)
                run = started.strftime("%Y%m%dT%H%M%S.%fZ-") + uuid.uuid4().hex
                os.mkdir(run, mode=0o700, dir_fd=backup_fd)
                with directory_fd(backup_fd, (run,)) as run_fd:
                    audit = {
                        "version": 1,
                        "operation": "migrate" if rollback_files is None else "prepare-rollback",
                        "rollbackFiles": str(rollback_files) if rollback_files is not None else None,
                        "home": str(home),
                        "startedAt": started.isoformat(),
                        "allowlist": source,
                        "entries": [
                            {
                                "path": relative,
                                "originalTarget": found["target"],
                                "backupPath": "files/" + relative,
                                "status": "pending",
                            }
                            for relative, found in selected
                        ],
                    }
                    write_audit(run_fd, audit)
                    moved = 0
                    for entry, (relative, expected) in zip(audit["entries"], selected):
                        parts = relative_parts(relative)
                        try:
                            with directory_fd(home_fd, parts[:-1]) as parent_fd:
                                # A user edit since collection is left in place.
                                inspect = matching_link if rollback_files is None else rollback_candidate
                                if inspect(parent_fd, parts[-1], relative) != expected:
                                    entry["status"] = "changed; preserved"
                                    if rollback_files is not None:
                                        write_audit(run_fd, audit)
                                        raise ValueError(f"file changed during rollback preparation: {relative}; retry preview")
                                else:
                                    with directory_fd(run_fd, ("files",) + parts[:-1], create=True) as dest_fd:
                                        os.rename(parts[-1], parts[-1], src_dir_fd=parent_fd, dst_dir_fd=dest_fd)
                                        os.fsync(dest_fd)
                                        os.fsync(parent_fd)
                                    entry["status"] = "moved"
                                    moved += 1
                        except OSError as error:
                            if error.errno in SKIPPABLE_PARENT_ERRORS:
                                entry["status"] = "changed; preserved"
                                if rollback_files is not None:
                                    write_audit(run_fd, audit)
                                    raise ValueError(f"parent changed during rollback preparation: {relative}") from error
                            else:
                                entry["status"] = "error"
                                entry["error"] = str(error)
                                write_audit(run_fd, audit)
                                raise
                        write_audit(run_fd, audit)
                    audit["completedAt"] = datetime.now(timezone.utc).isoformat()
                    write_audit(run_fd, audit)
                    return {"moved": moved, "backup": str(home.joinpath(*BACKUP_PARTS, run))}
            finally:
                os.close(lock_fd)
    finally:
        os.close(home_fd)


def home_manager_generation(unit_text):
    """Read the old unit without executing its setup script or activation."""
    commands = [line.removeprefix("ExecStart=") for line in unit_text.splitlines()
                if line.startswith("ExecStart=") and line != "ExecStart="]
    if len(commands) != 1:
        raise ValueError("expected one Home Manager ExecStart")
    arguments = shlex.split(commands[0])
    generations = [arg for arg in arguments if re.fullmatch(
        r"/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-home-manager-generation", arg)]
    if len(generations) != 1:
        raise ValueError("cannot identify the target Home Manager generation")
    return Path(generations[0])


def rollback_files_from_system(system, user):
    if not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_-]*\$?", user):
        raise ValueError("invalid Home Manager unit owner")
    unit = Path(system) / "etc/systemd/system" / f"home-manager-{user}.service"
    if not os.path.lexists(unit):
        return None
    generation = home_manager_generation(unit.read_text())
    files = (generation / "home-files").resolve(strict=True)
    if not files.is_dir() or not re.fullmatch(
        r"/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-home-manager-files", str(files)
    ):
        raise ValueError("target Home Manager file tree is unavailable")
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--rollback-system", type=Path,
                        help="prepare files for this old system instead of migrating to Hjem; preview by default")
    parser.add_argument("--user", help="Home Manager unit owner for --rollback-system")
    parser.add_argument("--apply", action="store_true", help="apply rollback preparation after reviewing its preview")
    args = parser.parse_args()
    try:
        if args.rollback_system is not None:
            if not args.user:
                raise ValueError("--rollback-system requires --user")
            files = rollback_files_from_system(args.rollback_system, args.user)
            if files is None:
                result = {"homeManager": False, "conflicts": [], "moved": 0, "backup": None}
            else:
                result = migrate(args.home, args.manifest, rollback_files=files, apply=args.apply)
        else:
            if args.apply or args.user:
                raise ValueError("--apply and --user require --rollback-system")
            result = migrate(args.home, args.manifest)
    except (OSError, ValueError) as error:
        print(f"Home Manager link migration failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
