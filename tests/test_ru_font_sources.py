#!/usr/bin/env python3
"""Check the CP866 reference/prototype, including corruption controls."""

import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("ru_fonts", ROOT / "tools/audit_ru_fonts.py")
fonts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fonts)


class RussianFontSources(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.outputs = fonts.audit()
        cls.report = json.loads(cls.outputs["font-audit.json"])

    def test_published_encoding_matches_independent_codec(self):
        manifest = json.loads((fonts.LOCALE / "manifest.json").read_text())
        self.assertEqual(manifest["unicode_mapping"],
                         [ord(bytes([i]).decode("cp866")) for i in range(256)])
        self.assertEqual(manifest["display_mapping"][:32], [
            0, 0x263a, 0x263b, 0x2665, 0x2666, 0x2663, 0x2660, 0x2022,
            0x25d8, 0x25cb, 0x25d9, 0x2642, 0x2640, 0x266a, 0x266b, 0x263c,
            0x25ba, 0x25c4, 0x2195, 0x203c, 0xb6, 0xa7, 0x25ac, 0x21a8,
            0x2191, 0x2193, 0x2192, 0x2190, 0x221f, 0x2194, 0x25b2, 0x25bc])
        self.assertEqual(manifest["display_mapping"][127], 0x2302)

    def test_review_artifacts_are_current(self):
        for name, data in self.outputs.items():
            self.assertEqual((fonts.LOCALE / "review" / name).read_bytes(), data, name)

    def test_candidate_gaps_are_explicit(self):
        for height, font in self.report["fonts"].items():
            self.assertEqual([g["byte"] for g in font["glyphs"]], list(range(256)))
            self.assertEqual([g["byte"] for g in font["glyphs"]
                              if g["status"] == "missing"],
                             [2, 8, 10] if height == "8" else [])
            self.assertFalse(any(g["status"] in ("clipped", "unexpected-blank")
                                 for g in font["glyphs"]))

    def test_bdf_baseline_and_clipping(self):
        # Synthetic geometry oracle independent of the installed font inputs:
        # a 2x2 glyph with BDF bottom at y=0 occupies DOS rows 8 and 9.
        rows, clipped = fonts.place_bdf((2, 2, 0, 0, [0x80, 0x40]), 14)
        self.assertEqual(rows, [0] * 8 + [0x40, 0x20] + [0] * 4)
        self.assertFalse(clipped)
        self.assertTrue(fonts.place_bdf((1, 1, 7, 0, [0x80]), 14)[1])
        self.assertTrue(fonts.place_bdf((1, 1, 0, 11, [0x80]), 14)[1])

    def test_short_font_unicode_aliases_and_yo(self):
        # Rows transcribed from the upstream 512_8_sans.txt contact sheet.
        short = self.report["fonts"]["8"]["glyphs"]
        self.assertEqual(short[0x80]["rows"], [0, 0x10, 0x28, 0x28, 0x44, 0x7c, 0x82, 0])
        self.assertEqual(short[0xf0]["rows"], [0x48, 0xfc, 0x80, 0xf0, 0x80, 0x80, 0xfc, 0])
        self.assertEqual(short[0xf1]["rows"], [0, 0x28, 0, 0x38, 0x44, 0x7c, 0x20, 0x10])

    def test_corruption_controls(self):
        with tempfile.TemporaryDirectory(prefix="ru-font-sources-") as work:
            directory = Path(work) / "ru"
            shutil.copytree(fonts.LOCALE, directory)
            path = directory / "manifest.json"
            original = path.read_text()
            manifest = json.loads(original)
            manifest["unicode_mapping"][0xf1] = 0x0435
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "published CP866"):
                fonts.audit(directory)
            manifest = json.loads(original)
            manifest["display_mapping"][0x80] = 0x0041
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "printable slot"):
                fonts.audit(directory)
            path.write_text(original)
            bitmap = directory / "upstream/512_8/512_8_sans.fnt"
            data = bytearray(bitmap.read_bytes())
            data[0x41 * 8] ^= 0x80
            bitmap.write_bytes(data)
            with self.assertRaisesRegex(ValueError, "source hash mismatch"):
                fonts.audit(directory)


if __name__ == "__main__":
    unittest.main()
