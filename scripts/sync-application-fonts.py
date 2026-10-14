"""Synchronize font preferences while preserving mutable application settings."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape


def jsonc_tokens(text):
    tokens = []
    decoder = json.JSONDecoder()
    i = 0
    while i < len(text):
        if text[i].isspace():
            i += 1
        elif text.startswith("//", i):
            end = text.find("\n", i)
            i = end if end >= 0 else len(text)
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end < 0:
                raise ValueError("Unterminated JSONC comment")
            i = end + 2
        elif text[i] == '"':
            value, end = decoder.raw_decode(text, i)
            tokens.append((i, end, "string", value))
            i = end
        elif text[i] in "{}[],:":
            tokens.append((i, i + 1, "punctuation", text[i]))
            i += 1
        else:
            match = re.match(r"[^\s{}\[\],:/]+", text[i:])
            if match is None:
                raise ValueError("Invalid JSONC token")
            end = i + len(match.group())
            tokens.append((i, end, "value", json.loads(text[i:end])))
            i = end
    return tokens


def parse_jsonc(text, tokens):
    pieces = []
    for index, token in enumerate(tokens):
        if token[2:] == ("punctuation", ",") and index + 1 < len(tokens):
            following = tokens[index + 1]
            if following[2] == "punctuation" and following[3] in ("]", "}"):
                continue
        pieces.append(text[token[0]:token[1]])
    return json.loads(" ".join(pieces))


def patch_jsonc(text, updates):
    tokens = jsonc_tokens(text)
    original = parse_jsonc(text, tokens)
    if not isinstance(original, dict):
        raise ValueError("Application settings must be a JSON object")
    properties = []
    i = 1
    while i < len(tokens) - 1:
        key = tokens[i]
        if key[2] != "string" or tokens[i + 1][3] != ":":
            raise ValueError("Invalid settings property")
        start = i + 2
        j = start
        depth = 0
        while j < len(tokens):
            token = tokens[j]
            if token[2] == "punctuation":
                if token[3] in ("{", "["):
                    depth += 1
                elif token[3] in ("}", "]"):
                    if depth == 0:
                        break
                    depth -= 1
                elif token[3] == "," and depth == 0:
                    break
            j += 1
        properties.append((key[3], tokens[start][0], tokens[j - 1][1]))
        i = j + (1 if tokens[j][3] == "," else 0)

    edits = [(start, end, json.dumps(updates[key], ensure_ascii=False))
             for key, start, end in properties if key in updates]
    missing = [key for key in updates if key not in original]
    if missing:
        prefix = ""
        if properties and tokens[-2][3] != ",":
            end = properties[-1][2]
            if end == tokens[-1][0]:
                prefix = ","
            else:
                edits.append((end, end, ","))
        insertion = prefix + "\n" + ",\n".join(
            "  " + json.dumps(key) + ": " + json.dumps(updates[key], ensure_ascii=False)
            for key in missing
        ) + "\n"
        edits.append((tokens[-1][0], tokens[-1][0], insertion))
    for start, end, replacement in sorted(edits, reverse=True):
        text = text[:start] + replacement + text[end:]
    assert parse_jsonc(text, jsonc_tokens(text)) == original | updates
    return text


def patch_qt(text, ui_font, mono_font, qt_version):
    match = re.search(r"(?ms)^\[Fonts\][^\n]*\n(.*?)(?=^\[|\Z)", text)
    body = match.group(1) if match else ""
    for key, family in (("general", ui_font), ("fixed", mono_font)):
        pattern = rf"(?m)^({key}\s*=\s*\"?)[^,\n\"]+(?=,)"
        if re.search(pattern, body):
            body = re.sub(pattern, lambda item: item.group(1) + family, body)
        else:
            suffix = ",11,-1,5,50,0,0,0,0,0,Regular" if qt_version == 5 else ",11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Regular"
            body += f'{key}="{family}{suffix}"\n'
    if match:
        return text[:match.start(1)] + body + text[match.end(1):]
    return text.rstrip() + "\n\n[Fonts]\n" + body


def patch_option(text, name, value, add=False):
    found = False
    def replace(match):
        nonlocal found
        tag = match.group()
        if not re.search(rf'\bname=[\"\']{re.escape(name)}[\"\']', tag):
            return tag
        found = True
        replacement = 'value="' + escape(value, {'"': '&quot;'}) + '"'
        if re.search(r'\bvalue=[\"\'][^\"\']*[\"\']', tag):
            return re.sub(r'\bvalue=[\"\'][^\"\']*[\"\']', lambda _: replacement, tag)
        return tag.replace("/>", replacement + " />")
    result = re.sub(r"<option\b[^>]*?/>", replace, text)
    if add and not found:
        result = result.rstrip() + f'\n    <option name="{name}" value="{escape(value)}" />\n  '
    return result


def patch_ide(text, component, mono_font, cjk_font):
    ET.fromstring(text)
    pattern = rf'(<component\b[^>]*\bname="{component}"[^>]*>)(.*?)(</component>)'
    def replace(match):
        body = patch_option(match.group(2), "FONT_FAMILY", mono_font, add=True)
        body = patch_option(body, "SECONDARY_FONT_FAMILY", cjk_font, add=True)
        return match.group(1) + body + match.group(3)
    result, count = re.subn(pattern, replace, text, flags=re.S)
    if count != 1:
        raise ValueError(f"Expected one {component} component")
    ET.fromstring(result)
    return result


def write_updated(path, text):
    original = path.read_bytes() if path.exists() else None
    data = text.encode()
    if original == data:
        return
    if path.is_symlink():
        raise ValueError(f"Refusing to replace managed settings symlink: {path}")
    if original is not None:
        backup = path.with_name(path.name + ".pre-font-unification-backup")
        if not backup.exists():
            shutil.copy2(path, backup)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(data)
        os.chmod(temporary, stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)
    print(f"Updated fonts: {path}")


def sync(config_home, ui_font, mono_font, cjk_font):
    dms = config_home / "DankMaterialShell/settings.json"
    write_updated(dms, patch_jsonc(dms.read_text() if dms.exists() else "{}", {
        "fontFamily": ui_font,
        "displayFontFamily": ui_font,
        "monoFontFamily": mono_font,
    }))
    for version in (5, 6):
        qt = config_home / f"qt{version}ct/qt{version}ct.conf"
        write_updated(qt, patch_qt(qt.read_text() if qt.exists() else "", ui_font, mono_font, version))
    # Create settings for the installed VS Code; update other existing variants.
    for application in ("Code", "Code - OSS", "VSCodium"):
        settings = config_home / application / "User/settings.json"
        if application != "Code" and not settings.exists():
            continue
        write_updated(settings, patch_jsonc(settings.read_text() if settings.exists() else "{}", {
            "editor.fontFamily": f"'{mono_font}', '{cjk_font}', monospace",
            "terminal.integrated.fontFamily": f"'{mono_font}', '{cjk_font}', monospace",
        }))
    for pattern in ("JetBrains/*", "Google/AndroidStudio*"):
        for profile in config_home.glob(pattern):
            for filename, component in (("editor-font.xml", "DefaultFont"), ("console-font.xml", "ConsoleFont")):
                path = profile / "options" / filename
                if path.exists():
                    write_updated(path, patch_ide(path.read_text(), component, mono_font, cjk_font))
            for path in profile.glob("colors/*.icls"):
                text = path.read_text()
                for name in ("EDITOR_FONT_NAME", "CONSOLE_FONT_NAME"):
                    text = patch_option(text, name, mono_font)
                ET.fromstring(text)
                write_updated(path, text)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-home", type=Path, required=True)
    parser.add_argument("--ui-font", required=True)
    parser.add_argument("--mono-font", required=True)
    parser.add_argument("--cjk-mono-font", required=True)
    args = parser.parse_args()
    sync(args.config_home, args.ui_font, args.mono_font, args.cjk_mono_font)
