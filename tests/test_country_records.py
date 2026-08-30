#!/usr/bin/env python3
"""Validate the retail DOS 5 BR/YU/CZ/PL/HU COUNTRY.SYS records."""

import hashlib
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COUNTRY = ROOT / "src/DEV/COUNTRY/COUNTRY.SYS"
OBJECT_LENGTH = {1: 48, 2: 138, 4: 138, 5: 32, 6: 267, 7: 13}
EXPECTED = {
    (55, 850): ("c2e5e8ea", "12e5f5dd", "b91f1865", "b2af3e8c", "a1e266cd", "8f5516f5"),
    (55, 437): ("c2e5e8ea", "d7c1281c", "7b41cc01", "7b41cc01", "a1e266cd", "8f5516f5"),
    (38, 852): ("41d87414", "ec343a79", "1c61018e", "26f0f704", "a1e266cd", "8f5516f5"),
    (38, 850): ("41d87414", "51e4970a", "b91f1865", "b2af3e8c", "a1e266cd", "8f5516f5"),
    (42, 852): ("a76fd8f1", "ec343a79", "1c61018e", "26f0f704", "a1e266cd", "8f5516f5"),
    (42, 850): ("a76fd8f1", "51e4970a", "b91f1865", "b2af3e8c", "a1e266cd", "8f5516f5"),
    (48, 852): ("0108093a", "ec343a79", "1c61018e", "26f0f704", "a1e266cd", "8f5516f5"),
    (48, 850): ("0108093a", "51e4970a", "b91f1865", "b2af3e8c", "a1e266cd", "8f5516f5"),
    (36, 852): ("a9e45c9a", "ec343a79", "1c61018e", "26f0f704", "a1e266cd", "8f5516f5"),
    (36, 850): ("a9e45c9a", "51e4970a", "b91f1865", "b2af3e8c", "a1e266cd", "8f5516f5"),
}


def word(data, offset):
    return struct.unpack_from("<H", data, offset)[0]


def short_hash(data):
    return hashlib.sha256(data).hexdigest()[:8]


def main():
    data = COUNTRY.read_bytes()
    table = struct.unpack_from("<I", data, 19)[0]
    position = table + 2
    records = {}
    for _ in range(word(data, table)):
        size, country, page = struct.unpack_from("<HHH", data, position)
        data_offset = word(data, position + 10)
        position += size + 2
        if (country, page) not in EXPECTED:
            continue
        item = data_offset + 2
        objects = {}
        for _ in range(word(data, data_offset)):
            item_size = word(data, item)
            kind = data[item + 2]
            target = word(data, item + 4)
            objects[kind] = short_hash(data[target:target + OBJECT_LENGTH[kind]])
            item += item_size + 2
        records[country, page] = tuple(objects[kind] for kind in (1, 6, 2, 4, 5, 7))
    if records != EXPECTED:
        raise AssertionError(f"DOS 5 country records differ: {records}")
    print("DOS 5 BR/YU/CZ/PL/HU country records: PASS")


if __name__ == "__main__":
    main()
