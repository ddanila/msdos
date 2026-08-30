#!/usr/bin/env python3
"""Check the DOS 5 Central European and Brazilian keyboard records."""

import hashlib
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KEYBOARD = ROOT / "src/DEV/KEYBOARD/KEYBOARD.SYS"


def word(data, offset):
    return struct.unpack_from("<H", data, offset)[0]


def main():
    data = KEYBOARD.read_bytes()
    maximums = struct.unpack_from("<HHH", data, 16)
    if maximums != (1120, 496, 640):
        raise AssertionError(f"wrong DOS 5 translation bounds: {maximums}")
    identifier_count, language_count = struct.unpack_from("<HH", data, 24)
    if (identifier_count, language_count) != (25, 23):
        raise AssertionError("wrong keyboard identifier/language counts")

    expected = {
        "BR": (274, 23536, ((850, 24321), (437, 24315))),
        "PL": (214, 24512, ((850, 25717), (852, 25899))),
        "CZ": (243, 26384, ((850, 27618), (852, 27791))),
        "SL": (245, 28240, ((850, 29474), (852, 29647))),
        "YU": (234, 30096, ((850, 31295), (852, 31447))),
        "HU": (208, 31904, ((850, 33108), (852, 33290))),
    }
    actual = {}
    position = 28
    for _ in range(language_count):
        code = data[position:position + 2].decode("ascii")
        entry = word(data, position + 2)
        position += 6
        if code not in expected:
            continue
        key_id = word(data, entry + 2)
        logic = word(data, entry + 4)
        code_pages = tuple(
            (word(data, entry + 10 + index * 6),
             word(data, entry + 12 + index * 6))
            for index in range(data[entry + 9])
        )
        actual[code] = (key_id, logic, code_pages)
    if actual != expected:
        raise AssertionError(f"DOS 5 keyboard record mismatch: {actual}")

    digest = hashlib.sha256(data[23536:33776]).hexdigest()
    expected_digest = "f4795de7d9b4251dfd6b87441459f346c355186d467d3328b299c00c67b3225b"
    if digest != expected_digest:
        raise AssertionError(f"DOS 5 keyboard table payload mismatch: {digest}")
    print("DOS 5 BR/PL/CZ/SL/YU/HU keyboard records: PASS")


if __name__ == "__main__":
    main()
