#!/usr/bin/env python3
"""Validate CP775 CPI structure, national glyphs and supported box edges."""

import hashlib
import json
from pathlib import Path
import subprocess
import unittest

from test_ru_cpi import BOX_EDGES, parse_cpi

ROOT = Path(__file__).resolve().parents[1]
CPI = ROOT / "src/DEV/DISPLAY/EGA/EGA775.CPI"

# Fixed bitmap expectations for tilde, cedilla and ogonek in both cases.
# Keep these independent of the packer and its selected-font review output.
ROWS = {
    8: {0xe4: "3458003844443800", 0xe5: "6498788484847800",
        0x85: "0010003a443c0438", 0x95: "007884809c847820",
        0xd0: "000000748898680c", 0xb5: "00102828447c8203"},
    14: {0xe4: "001a2c001c222222221c00000000", 0xe5: "1a2c001c22222222221c00000000",
         0x85: "000408001e222222221e02021c00", 0x95: "00001c2220202622221c00081000",
         0xd0: "000000001c222222261a04060000", 0xb5: "00001c2222223e22222204060000"},
    16: {0xe4: "00001a2c001c222222221c0000000000", 0xe5: "001a2c001c22222222221c0000000000",
         0x85: "00000408001e222222221e02021c0000", 0x95: "0000001c2220202622221c0008100000",
         0xd0: "00000000001c222222261a0406000000", 0xb5: "0000001c2222223e2222220406000000"},
}


def check_fonts(fonts):
    edges = {bytes([b]).decode("cp866"): styles for b, styles in enumerate(BOX_EDGES, 0xb3)}
    for height, glyphs in fonts.items():
        assert [b for b, rows in enumerate(glyphs) if not any(rows)] == [0, 32, 255]
        for byte, rows in ROWS[height].items():
            assert glyphs[byte].hex() == rows, f"national glyph {height}/{byte:02X}"
        horizontal = [set(), {height // 2 - 1}, {height // 2 - 2, height // 2}]
        for byte in range(128, 256):
            char = bytes([byte]).decode("cp775")
            if char not in edges:
                continue
            up, right, down, left = map(int, edges[char])
            rows = glyphs[byte]
            assert rows[0] == [0, 0x10, 0x28][up], f"top edge {height}/{byte:02X}"
            assert rows[-1] == [0, 0x10, 0x28][down], f"bottom edge {height}/{byte:02X}"
            assert {y for y, bits in enumerate(rows) if bits & 0x80} == horizontal[left]
            assert {y for y, bits in enumerate(rows) if bits & 1} == horizontal[right]
        for byte, pair in ((0xb0, b"\x88\x22"), (0xb1, b"\xaa\x55"), (0xb2, b"\x77\xdd")):
            assert glyphs[byte] == pair * (height // 2)
        assert glyphs[0xdb] == bytes([255]) * height


class BalticCpi(unittest.TestCase):
    def test_structure_glyphs_and_edges(self):
        check_fonts(parse_cpi(CPI.read_bytes(), 775))

    def test_review_matches_build(self):
        subprocess.run(["python3", ROOT / "tools/build_ru_cpi.py", "--locale",
                        ROOT / "locales/baltic", "--check"], check=True)
        report = json.loads((ROOT / "locales/baltic/review/selected-fonts.json").read_text())
        self.assertEqual(report["cpi_sha256"], hashlib.sha256(CPI.read_bytes()).hexdigest())

    def test_wrong_glyph_and_broken_border_detected(self):
        fonts = parse_cpi(CPI.read_bytes(), 775)
        fonts[16][0xe4] = fonts[16][0xe5]
        with self.assertRaisesRegex(AssertionError, "national glyph"):
            check_fonts(fonts)
        fonts = parse_cpi(CPI.read_bytes(), 775)
        fonts[14][0xb3] = b"\0" + fonts[14][0xb3][1:]
        with self.assertRaisesRegex(AssertionError, "top edge"):
            check_fonts(fonts)

    def test_wrong_page_and_truncated_payload_rejected(self):
        data = bytearray(CPI.read_bytes())
        data[41:43] = (866).to_bytes(2, "little")
        with self.assertRaises(AssertionError):
            parse_cpi(data, 775)
        with self.assertRaises(AssertionError):
            parse_cpi(CPI.read_bytes()[:9000], 775)


if __name__ == "__main__":
    unittest.main()
