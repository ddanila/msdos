#!/usr/bin/env python3
"""Extract Russian compatibility facts from private DOS 6.22 reference files.

The retail files are optional external inputs and must not be committed.
Only data-table expectations are retained, never resident keyboard code or
retail fonts. This tool is independent of the locale builders.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct


class Reader:
    def __init__(self, path):
        self.data = path.read_bytes()

    def take(self, offset, size):
        if offset < 0 or size < 0 or offset + size > len(self.data):
            raise ValueError("reference record outside file")
        return self.data[offset:offset + size]

    def word(self, offset):
        return struct.unpack("<H", self.take(offset, 2))[0]

    def pointer(self, offset):
        return struct.unpack("<I", self.take(offset, 4))[0]

    def provenance(self, name):
        return {"name": name, "size": len(self.data),
                "sha256": hashlib.sha256(self.data).hexdigest(),
                "edition": "English MS-DOS 6.22, media timestamp 1994-05-31 06:22"}


def country_records(path):
    reader = Reader(path)
    if reader.take(0, 8) != b"\xffCOUNTRY":
        raise ValueError("COUNTRY.SYS signature")
    table = reader.pointer(19)
    position = table + 2
    records = {}
    for _ in range(reader.word(table)):
        size = reader.word(position)
        country, page = reader.word(position + 2), reader.word(position + 4)
        record = reader.pointer(position + 10)
        position += size + 2
        if country != 7 or page not in (866, 437, 850):
            continue
        objects = {}
        entry = record + 2
        for _ in range(reader.word(record)):
            kind = reader.take(entry + 2, 1)[0]
            target = reader.pointer(entry + 4)
            length = reader.word(target + 8)
            objects[str(kind)] = {
                "offset": target,
                "signature": reader.take(target, 8).hex(),
                "payload": reader.take(target + 10, length).hex(),
            }
            entry += reader.word(entry) + 2
        records[str(page)] = {"offset": record, "objects": objects}
    if set(records) != {"866", "437", "850"}:
        raise ValueError("missing Russian country reference records")
    return reader.provenance("COUNTRY.SYS"), records


def keyboard_tables(path):
    reader = Reader(path)
    if reader.take(0, 8) != b"\xffKEYB   ":
        raise ValueError("KEYBRD2.SYS signature")
    entry = None
    for index in range(reader.word(26)):
        position = 28 + index * 6
        if reader.take(position, 2) == b"RU":
            entry = reader.pointer(position + 2)
    if entry is None or reader.take(entry, 2) != b"RU":
        raise ValueError("missing RU keyboard entry")
    page = None
    for index in range(reader.take(entry + 9, 1)[0]):
        position = entry + 10 + index * 6
        if reader.word(position) == 866:
            page = reader.pointer(position + 2)
    if page is None or reader.word(page + 2) != 866:
        raise ValueError("missing RU/866 keyboard section")
    states = {}
    position, end = page + 4, page + reader.word(page)
    while reader.word(position):
        length = reader.word(position)
        if length < 9 or position + length > end:
            raise ValueError("invalid keyboard state length")
        state = reader.take(position + 2, 1)[0]
        keyboard_mask = reader.word(position + 3)
        table = position + 7
        translations = []
        while reader.word(table):
            size = reader.word(table)
            options, count = reader.take(table + 2, 2)
            # This reference uses explicit scan/ASCII pairs, with optional
            # zero scan output. Do not interpret a different table as this one.
            if options not in (0xc0, 0xe0) or size != 4 + count * 2:
                raise ValueError("unexpected Russian translate table format")
            if table + size > position + length - 2:
                raise ValueError("translate table outside state")
            for index in range(count):
                scan, byte = reader.take(table + 4 + index * 2, 2)
                translations.append({"scan": scan, "byte": byte,
                                     "bios_scan": 0 if options & 0x20 else scan})
            table += size
        states[str(state)] = {"keyboard_mask": keyboard_mask,
                              "translations": translations}
        position += length
    if position != end - 2 or set(states) != {"3", "4", "5", "6", "7"}:
        raise ValueError("unexpected Russian keyboard states")
    return reader.provenance("KEYBRD2.SYS"), {
        "identifier": reader.word(entry + 2), "entry_offset": entry,
        "cp866_offset": page, "states": states,
    }


def capture(directory):
    country_source, countries = country_records(directory / "COUNTRY.SYS")
    keyboard_source, keyboard = keyboard_tables(directory / "KEYBRD2.SYS")
    return {"schema_version": 1, "sources": [country_source, keyboard_source],
            "country_records": countries, "keyboard": keyboard}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference_directory", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = (json.dumps(capture(args.reference_directory), indent=2) + "\n").encode()
    if args.check:
        if args.output.read_bytes() != result:
            raise SystemExit("Russian contract differs from reference media")
    else:
        args.output.write_bytes(result)


if __name__ == "__main__":
    main()
