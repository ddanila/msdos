#!/usr/bin/env python3
"""Capture CP775 input facts from the pinned KEY language references.

This intentionally does not emit Microsoft KEYB macros or resident code.
Only the syntax used by the selected CP775 profiles is accepted.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LOCALE = ROOT / "locales/baltic"


def sections(data):
    result, active = {}, None
    # Latin-1 is a byte-preserving container. str.splitlines/split would
    # incorrectly treat CP775 bytes 85/A0 as Unicode whitespace.
    for raw in data.split(b"\n"):
        line = raw.decode("latin-1").rstrip("\r").split(";", 1)[0].strip(" \t")
        if not line:
            continue
        if line.startswith("["):
            if not line.endswith("]"):
                raise ValueError("malformed section header")
            name = line[1:-1].lower()
            if name in result:
                raise ValueError("duplicate section")
            active = result[name] = []
        elif active is None:
            raise ValueError("data outside section")
        else:
            active.append(re.split(r"[ \t]+", line))
    return result


def character(text):
    """Return the leading KEY character token and unconsumed suffix."""
    if not text:
        raise ValueError("missing character")
    if text.startswith("#"):
        number = re.match(r"#([0-9]+)", text)
        if number:
            value = int(number[1])
            if value > 255:
                raise ValueError("character outside byte range")
            return value, text[number.end():]
        if len(text) < 2:
            raise ValueError("incomplete escape")
        return ord(text[1]), text[2:]
    return ord(text[0]), text[1:]


def effect(token, scan, paired):
    if paired:
        prefix, token = token.split("/", 1)
        scan = int(prefix)
    if not 0 <= scan <= 255:
        raise ValueError("scan code outside byte range")
    if token == "!0":
        return None  # Search the general table, then the BIOS mapping.
    if re.fullmatch(r"!C[1-9][0-9]*", token):
        return {"kind": "dead", "id": int(token[2:])}
    if token.startswith("!"):
        raise ValueError(f"unsupported reference command: {token}")
    byte, rest = character(token)
    if rest:
        raise ValueError(f"trailing character data: {token!r}")
    return {"kind": "character", "byte": byte, "scan": scan}


def key_rows(rows):
    keys = {}
    for row in rows:
        match = re.fullmatch(r"([0-9]+)([CS]*)", row[0])
        if not match:
            raise ValueError(f"unsupported key flags: {row[0]}")
        scan, flags = int(match[1]), match[2]
        if scan in keys:
            raise ValueError("duplicate physical scan code")
        keys[scan] = {"caps": "C" in flags,
                      "effects": [effect(t, scan, "S" in flags) for t in row[1:]]}
    return keys


def capture(data):
    blocks = sections(data)
    mapping = next(row for row in blocks["submappings"] if row[0] == "775")
    common_name = next(row[1] for row in blocks["submappings"] if row[0] == "0")
    common = key_rows(blocks["keys:" + common_name.lower()])
    special = {} if mapping[1] == "-" else key_rows(blocks["keys:" + mapping[1].lower()])
    planes = ["normal", "shift"] + [" ".join(row) for row in blocks["planes"]]
    keys = {}
    for scan in sorted(common.keys() | special.keys()):
        effects = []
        for plane in range(len(planes)):
            selected = None
            for table in (special, common):
                row = table.get(scan, {})
                values = row.get("effects", [])
                if plane < len(values) and values[plane] is not None:
                    selected = dict(values[plane], caps=row["caps"])
                    break
            effects.append(selected)
        keys[str(scan)] = effects
    dead = {}
    if len(mapping) > 2:
        for index, row in enumerate(blocks["diacritics:" + mapping[2].lower()], 1):
            accent, rest = character(row[0])
            if rest:
                raise ValueError("invalid dead-key literal")
            pairs = {}
            for token in row[1:]:
                first, rest = character(token)
                second, rest = character(rest)
                if rest or str(first) in pairs:
                    raise ValueError("invalid or duplicate composition")
                pairs[str(first)] = second
            dead[str(index)] = {"literal": accent, "pairs": pairs}
    for effects in keys.values():
        for item in effects:
            if item and item["kind"] == "dead" and str(item["id"]) not in dead:
                raise ValueError("missing composition table")
    return {"planes": planes, "keys": keys, "dead_keys": dead,
            "names": [" ".join(row) for row in blocks["general"]]}


def materialize(directory=LOCALE):
    sources = json.loads((directory / "keyboard-sources.json").read_text())
    for source in sources["sources"]:
        if hashlib.sha256((directory / source["path"]).read_bytes()).hexdigest() != source["sha256"]:
            raise ValueError(f"reference hash mismatch: {source['path']}")
    result = {"schema_version": 1, "status": "captured-reference-runtime-unqualified",
              "scope": "CP775 overrides, composition and scan-code facts; null means BIOS fallback. Physical modifier selection, US mode and legacy hardware require separate guest qualification.",
              "profiles": {}}
    for language, name in (("et", "Et.key"), ("lv", "Lv.key"), ("lt", "Lt221.key")):
        path = directory / "upstream/keydos" / name
        result["profiles"][language] = dict(capture(path.read_bytes()),
                                            source_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    return (json.dumps(result, indent=2) + "\n").encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = materialize()
    path = LOCALE / "review/keyboard-expectations.json"
    if args.check:
        if not path.exists() or path.read_bytes() != data:
            raise SystemExit("stale Baltic keyboard expectations")
    else:
        path.write_bytes(data)


if __name__ == "__main__":
    main()
