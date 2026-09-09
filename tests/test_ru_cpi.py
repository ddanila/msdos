#!/usr/bin/env python3
"""Validate the CP866 CPI structure, glyph slots and every box-drawing edge."""

import hashlib
import json
from pathlib import Path
import struct
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
CPI = ROOT / "src/DEV/DISPLAY/EGA/EGA866.CPI"

# Up/right/down/left edge styles, independently specified from Unicode names.
BOX_EDGES = """
1010 1011 1012 2021 0021 0012 2022 2020 0022 2002 2001 1002 0011
1100 1101 0111 1110 0101 1111 1210 2120 2200 0220 2202 0222 2220
0202 2222 1202 2101 0212 0121 2100 1200 0210 0120 2121 1212 1001 0110
""".split()

# Independently transcribed upstream rows after the stated baseline placement.
EXPECTED_ROWS = {
    8: {0x80: "00102828447c8200", 0xf0: "48fc80f08080fc00", 0xf1: "00280038447c2010"},
    14: {0x80: "0000080814141c22222200000000", 0xf0: "14003e20203c2020203e00000000",
         0xf1: "000014001c223e20221c00000000"},
    16: {0x80: "000000080814141c2222220000000000", 0xf0: "0014003e20203c2020203e0000000000",
         0xf1: "00000014001c223e20221c0000000000"},
}


def parse_cpi(data):
    assert data[:16] == b"\xffFONT   " + bytes(8), "file signature/reserved bytes"
    assert struct.unpack_from("<HBIH", data, 16) == (1, 1, 23, 1), "file pointers"
    size, following, device, name, page, reserved, info = struct.unpack_from("<HIH8sH6sI", data, 25)
    assert (size, device, name, page, reserved, info) == (28, 1, b"EGA     ", 866, bytes(6), 53)
    kind, count, length = struct.unpack_from("<HHH", data, info)
    assert (kind, count, length) == (1, 3, 9746), "font header"
    assert following == info + 6 + length <= len(data), "next entry pointer"
    position, fonts = info + 6, {}
    for expected_height in (16, 14, 8):
        height, width, aspect_x, aspect_y, chars = struct.unpack_from("<BBBBH", data, position)
        assert (height, width, aspect_x, aspect_y, chars) == (expected_height, 8, 0, 0, 256)
        position += 6
        payload = data[position:position + chars * height]
        assert len(payload) == chars * height
        fonts[height] = [payload[i * height:(i + 1) * height] for i in range(chars)]
        position += chars * height
    assert position == following, "font payload extent"
    return fonts


def check_glyphs(fonts):
    for height, glyphs in fonts.items():
        assert len(glyphs) == 256
        assert [i for i, rows in enumerate(glyphs) if not any(rows)] == [0, 32, 255]
        for byte, rows in EXPECTED_ROWS[height].items():
            assert glyphs[byte].hex() == rows, f"glyph slot {height}/{byte:02X}"
        vertical = [0, 0x10, 0x28]
        horizontal = [set(), {height // 2 - 1}, {height // 2 - 2, height // 2}]
        for byte, styles in enumerate(BOX_EDGES, 0xb3):
            up, right, down, left = map(int, styles)
            rows = glyphs[byte]
            assert rows[0] == vertical[up], f"top edge {height}/{byte:02X}"
            assert rows[-1] == vertical[down], f"bottom edge {height}/{byte:02X}"
            assert {y for y, bits in enumerate(rows) if bits & 0x80} == horizontal[left]
            assert {y for y, bits in enumerate(rows) if bits & 1} == horizontal[right]
        assert glyphs[0xdb] == bytes([255]) * height
        assert glyphs[0xdc] == bytes(height // 2) + bytes([255]) * (height // 2)
        assert glyphs[0xdf] == bytes([255]) * (height // 2) + bytes(height // 2)
        for byte, pair in [(0xb0, b"\x88\x22"), (0xb1, b"\xaa\x55"), (0xb2, b"\x77\xdd")]:
            assert glyphs[byte] == pair * (height // 2)


class RussianCpi(unittest.TestCase):
    def test_structure_and_glyphs(self):
        check_glyphs(parse_cpi(CPI.read_bytes()))

    def test_reviews_match_build(self):
        subprocess.run(["python3", ROOT / "tools/build_ru_cpi.py", "--check"], check=True)
        review = json.loads((ROOT / "locales/ru/review/selected-fonts.json").read_text())
        self.assertEqual(review["cpi_sha256"], hashlib.sha256(CPI.read_bytes()).hexdigest())

    def test_wrong_glyph_and_border_controls(self):
        fonts = parse_cpi(CPI.read_bytes())
        fonts[16][0xf0], fonts[16][0xf1] = fonts[16][0xf1], fonts[16][0xf0]
        with self.assertRaisesRegex(AssertionError, "glyph slot"):
            check_glyphs(fonts)
        fonts = parse_cpi(CPI.read_bytes())
        fonts[14][0xb3] = b"\0" + fonts[14][0xb3][1:]
        with self.assertRaisesRegex(AssertionError, "top edge"):
            check_glyphs(fonts)

    def test_truncation_and_pointer_controls(self):
        data = CPI.read_bytes()
        with self.assertRaises(AssertionError):
            parse_cpi(data[:100])
        changed = bytearray(data)
        changed[49] ^= 1
        with self.assertRaises(AssertionError):
            parse_cpi(changed)


if __name__ == "__main__":
    unittest.main()
