"""Preserve conflicting static Fcitx5 files before Hjem takes ownership."""

import argparse
import json
import os
from pathlib import Path
import tempfile


def migrate(files, state_dir):
    pending = []
    for entry in files:
        target = Path(entry["target"])
        source = entry["source"]
        # Refuse directory collisions or symlinked parents before moving any file.
        if not target.is_absolute() or any(parent.is_symlink() for parent in target.parents):
            raise ValueError(f"Unsafe managed file path: {target}")
        if target.is_dir() and not target.is_symlink():
            raise ValueError(f"Managed file is a directory: {target}")
        if target.is_symlink() and os.readlink(target) == source:
            continue
        if os.path.lexists(target):
            pending.append((target, source))
    if not pending:
        return None

    state_dir = Path(state_dir)
    state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup = Path(tempfile.mkdtemp(prefix="config-handover-", dir=state_dir))
    records = []
    for index, (target, source) in enumerate(pending):
        saved = backup / f"{index}-{target.name}"
        record = {"target": str(target), "source": source, "backup": str(saved)}
        records.append(record)
    # Record destinations first so a partially completed move remains auditable.
    (backup / "manifest.json").write_text(json.dumps(records, indent=2) + "\n")
    for record in records:
        Path(record["target"]).rename(record["backup"])
    print(f"Preserved {len(records)} Fcitx5 configuration file(s) in {backup}")
    return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    args = parser.parse_args()
    migrate(json.loads(args.manifest.read_text()), args.state_dir)


if __name__ == "__main__":
    main()
