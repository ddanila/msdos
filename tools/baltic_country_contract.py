#!/usr/bin/env python3
"""Materialize the explicit Baltic DOS country contract for independent review.

This emits reference expectations, not assembler or an installed COUNTRY.SYS.
National ordering and compatibility limits live in country-contract.json.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
LOCALE = ROOT / "locales/baltic"


def tables(profile, page):
    codec = f"cp{page}"
    chars = [bytes([i]).decode(codec) for i in range(256)]
    uppercase = list(range(256))
    for byte, char in enumerate(chars):
        try:
            encoded = char.upper().encode(codec)
        except UnicodeEncodeError:
            continue
        if len(encoded) == 1:
            uppercase[byte] = encoded[0]
    groups = profile["collation_groups"]
    if len(set(groups)) != len(groups):
        raise ValueError("duplicate collation group")
    members = {group: [] for group in groups}
    other = []
    for byte, char in enumerate(chars):
        if not char.isalpha():
            other.append([byte])
            continue
        # These two CP775 characters cannot use a single-byte capital partner.
        group = char if char in ("\u00df", "\u00b5") else char.upper()
        if group not in members:
            raise ValueError(f"unassigned letter group: CP{page} U+{ord(char):04X}")
        members[group].append(byte)
    ordered = other + [members[group] for group in groups if members[group]]
    collate = [None] * 256
    for weight, group in enumerate(ordered):
        for byte in group:
            collate[byte] = weight
    assert None not in collate and max(collate) < 256
    return uppercase, collate


def country_info(profile, page):
    def terminated(value, size):
        data = value.encode(f"cp{page}")
        if len(data) >= size:
            raise ValueError("country string does not fit its DOS field")
        return data.ljust(size, b"\0")

    data = struct.pack("<HHH", profile["country_id"], page,
                       {"MDY": 0, "DMY": 1, "YMD": 2}[profile["date_order"]])
    data += terminated(profile["currency_symbol"], 5)
    for field in ("thousands_separator", "decimal_separator", "date_separator", "time_separator"):
        data += terminated(profile[field], 2)
    data += bytes([profile["currency_format"], profile["currency_digits"],
                   int(profile["time_24_hour"])])
    data += bytes(4)  # DOS fills the case-conversion callback at runtime.
    data += terminated(profile["list_separator"], 2) + bytes(10)
    return data


def materialize(directory=LOCALE):
    source = directory / "country-contract.json"
    contract = json.loads(source.read_text())
    for item in contract["sources"]:
        if "path" in item:
            if hashlib.sha256((directory / item["path"]).read_bytes()).hexdigest() != item["sha256"]:
                raise ValueError(f"source hash mismatch: {item['path']}")
    result = {"schema_version": 1, "status": "selected-expectations-runtime-unqualified",
              "contract_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "countries": {}}
    for language, profile in contract["profiles"].items():
        pages = {}
        for page in profile["supported_code_pages"]:
            uppercase, collate = tables(profile, page)
            pages[str(page)] = {"country_info_hex": country_info(profile, page).hex(),
                                "uppercase_hex": bytes(uppercase).hex(),
                                "filename_uppercase_hex": bytes(uppercase).hex(),
                                "collation_hex": bytes(collate).hex()}
        result["countries"][language] = pages
    return (json.dumps(result, indent=2) + "\n").encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = materialize()
    path = LOCALE / "review/country-expectations.json"
    if args.check:
        if not path.exists() or path.read_bytes() != data:
            raise SystemExit("stale Baltic country expectations")
    else:
        path.write_bytes(data)


if __name__ == "__main__":
    main()
