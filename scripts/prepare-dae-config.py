"""Add declared LAN interfaces to a private DAE config without rewriting policy."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import sys
import tempfile


LITERALS = re.compile(r"'(?:(?:\\.)|[^'\\])*'|\"(?:(?:\\.)|[^\"\\])*\"|\#[^\n]*")
KEY = re.compile(r"\b[A-Za-z_][A-Za-z_0-9]*\s*:")


def merge_lan_interfaces(text, interfaces):
    # Preserve offsets while hiding quoted braces, node URLs and comments.
    literals = list(LITERALS.finditer(text))
    masked = LITERALS.sub(lambda match: " " * len(match.group()), text)
    comments = [match.start() for match in literals if match.group().startswith("#")]
    blocks, depth, opening = [], 0, None
    for match in re.finditer(r"[{}]", masked):
        if match.group() == "{":
            if depth == 0:
                opening = match.end() if re.search(r"\bglobal\s*$", masked[:match.start()]) else None
            depth += 1
        else:
            depth -= 1
            if depth < 0:
                raise ValueError("Unbalanced config sections")
            if depth == 0 and opening is not None:
                blocks.append((opening, match.start()))
    if depth:
        raise ValueError("Unbalanced config sections")
    values, declarations = [], []
    for block_index, (begin, end) in enumerate(blocks):
        for match in re.finditer(r"\blan_interface\s*:", masked[begin:end]):
            key_start, value_start = begin + match.start(), begin + match.end()
            value_end = masked.find("\n", value_start, end)
            if value_end == -1:
                value_end = end
            next_key = KEY.search(masked, value_start, value_end)
            if next_key is not None:
                value_end = next_key.start()
            value_end = min([value_end] + [offset for offset in comments if value_start <= offset < value_end])
            raw = text[value_start:value_end]
            lexer = shlex.shlex(raw, posix=True)
            lexer.whitespace = ", \t\r\n"
            lexer.whitespace_split = True
            lexer.commenters = ""
            for token in lexer:
                values.extend(item.strip() for item in token.split(",") if item.strip())
            left = value_start + len(raw) - len(raw.lstrip())
            right = value_start + len(raw.rstrip())
            if not raw.strip():
                left = right = value_start
            declarations.append((block_index, key_start, left, right))
    merged = list(dict.fromkeys(values + list(interfaces)))
    value = json.dumps(",".join(merged))
    # Keep the authoritative declaration in the final global section.
    anchors = [entry for entry in declarations if entry[0] == len(blocks) - 1]
    anchor = anchors[-1] if anchors else None
    changes = []
    for entry in declarations:
        _, key_start, value_start, value_end = entry
        changes.append((value_start, value_end, value) if entry == anchor else (key_start, value_end, ""))
    if anchor is None:
        if blocks:
            offset = blocks[-1][1]
            changes.append((offset, offset, f"\n  lan_interface: {value}\n"))
        else:
            changes.append((len(text), len(text), f"\nglobal {{\n  lan_interface: {value}\n}}\n"))
    for start, end, replacement in sorted(changes, reverse=True):
        text = text[:start] + replacement + text[end:]
    return text


def prepare(source, destination, interfaces):
    for interface in interfaces:
        if not re.fullmatch(r"[A-Za-z0-9_.:-]{1,15}", interface):
            raise ValueError("Invalid declared LAN interface")
    content = merge_lan_interfaces(Path(source).read_text(), interfaces)
    destination = Path(destination)
    fd, temporary = tempfile.mkstemp(prefix=".config-", suffix=".dae", dir=destination.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    finally:
        Path(temporary).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--lan-interface", action="append", required=True)
    args = parser.parse_args()
    try:
        prepare(args.source, args.output, args.lan_interface)
    except (OSError, ValueError):
        # Parser diagnostics must never quote private config lines or node URLs.
        sys.exit("Unable to prepare private DAE config; check its global section and file permissions")


if __name__ == "__main__":
    main()
