"""Select the locked CPython 3.12 Linux wheels; print a fetchurl manifest.

Run with Python's packaging module and uv on PATH. The source must be the
locked michi-ocr input, not the mutable development checkout. Missing upstream
hashes are reported and must be prefetched separately, then supplied as JSON.
"""

import argparse
import hashlib
import json
import subprocess
import tomllib
from pathlib import Path
from urllib.parse import unquote, urlparse

from packaging.markers import default_environment
from packaging.requirements import Requirement
from packaging.tags import compatible_tags, cpython_tags
from packaging.utils import canonicalize_name, parse_wheel_filename


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--extra-hashes", type=Path)
    args = parser.parse_args()
    lock = tomllib.loads((args.source / "uv.lock").read_text())
    extra_hashes = json.loads(args.extra_hashes.read_text()) if args.extra_hashes else {}
    requirements = subprocess.check_output(
        [
            "uv", "export", "--project", str(args.source), "--frozen", "--offline",
            "--extra", "local", "--no-dev", "--no-emit-project", "--no-hashes",
            "--no-header", "--no-annotate",
        ],
        text=True,
    )
    environment = default_environment() | {
        "python_version": "3.12", "python_full_version": "3.12.0",
        "implementation_name": "cpython", "implementation_version": "3.12.0",
        "platform_python_implementation": "CPython", "sys_platform": "linux",
        "os_name": "posix", "platform_machine": "x86_64", "platform_system": "Linux",
    }
    platforms = [f"manylinux_2_{n}_x86_64" for n in range(38, 4, -1)]
    platforms += ["manylinux2014_x86_64", "manylinux2010_x86_64", "manylinux1_x86_64", "linux_x86_64"]
    tags = list(cpython_tags((3, 12), platforms=platforms))
    tags += list(compatible_tags((3, 12), interpreter="cp312", platforms=platforms))
    ranks = {tag: rank for rank, tag in enumerate(tags)}
    result = []
    for line in requirements.splitlines():
        requirement = Requirement(line)
        if requirement.marker and not requirement.marker.evaluate(environment):
            continue
        candidates = [
            package for package in lock["package"]
            if canonicalize_name(package["name"]) == canonicalize_name(requirement.name)
            and package["version"] in requirement.specifier
        ]
        if len(candidates) != 1:
            raise ValueError(f"Ambiguous lock entry: {requirement}")
        wheels = []
        for wheel in candidates[0].get("wheels", []):
            filename = unquote(Path(urlparse(wheel["url"]).path).name)
            wheel_tags = parse_wheel_filename(filename)[3]
            matching = [ranks[tag] for tag in wheel_tags if tag in ranks]
            if matching:
                wheels.append((min(matching), filename, wheel))
        if not wheels:
            raise ValueError(f"No CPython 3.12 Linux wheel: {requirement}")
        _, filename, wheel = min(wheels, key=lambda item: item[0])
        hash_value = wheel.get("hash") or extra_hashes.get(wheel["url"])
        if not hash_value:
            raise ValueError(f"Prefetch and supply SHA256 for {wheel['url']}")
        result.append({"name": filename, "url": wheel["url"], "hash": hash_value})
    print(json.dumps({
        "lockHash": hashlib.sha256((args.source / "uv.lock").read_bytes()).hexdigest(),
        "wheels": result,
    }, indent=2))


if __name__ == "__main__":
    main()
