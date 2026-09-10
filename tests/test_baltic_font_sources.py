#!/usr/bin/env python3
"""Check the CP775 encoding and candidate fonts before producing a CPI."""

import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LOCALE = ROOT / "locales/baltic"
spec = importlib.util.spec_from_file_location("locale_fonts", ROOT / "tools/audit_ru_fonts.py")
fonts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fonts)


class BalticFontSources(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((LOCALE / "manifest.json").read_text())
        cls.outputs = fonts.audit(LOCALE)
        cls.report = json.loads(cls.outputs["font-audit.json"])

    def test_encoding_against_independent_codec(self):
        mapping = self.manifest["unicode_mapping"]
        self.assertEqual(mapping, [ord(bytes([i]).decode("cp775")) for i in range(256)])
        # CP775 replaces several CP437 box slots with Baltic letters.
        self.assertEqual(mapping[0xb5:0xb9], [0x0104, 0x010c, 0x0118, 0x0116])
        self.assertNotIn(0x20ac, mapping)
        display = self.manifest["display_mapping"]
        self.assertEqual(display[0], 0)
        self.assertEqual(display[1], 0x263a)
        self.assertEqual(display[127], 0x2302)
        self.assertEqual(display[128:], mapping[128:])

    def test_all_language_letters_in_both_cases(self):
        # Fixed CP775 byte expectations checked alongside the independent codec.
        expected = {
            "et": ("8494e481d5d8", "8e99e59abecf"),
            "lv": ("83d189858ce9ebecd5d7d8", "a0b6ed95a1e8eaeebec7cf"),
            "lt": ("d0d1d2d3d4d5d6d7d8", "b5b6b7b8bdbec6c7cf"),
        }
        self.assertEqual(set(self.manifest["languages"]), set(expected))
        for language, (lower, upper) in expected.items():
            record = self.manifest["languages"][language]
            self.assertEqual(record["required_lowercase"].encode("cp775").hex(), lower)
            self.assertEqual(record["required_uppercase"].encode("cp775").hex(), upper)
            record["sample_text"].encode("cp775", errors="strict")
            slots = bytes.fromhex(lower + upper)
            for font in self.report["fonts"].values():
                for slot in slots:
                    self.assertEqual(font["glyphs"][slot]["status"], "present")

    def test_candidate_gaps_are_explicit(self):
        for height, font in self.report["fonts"].items():
            self.assertEqual([g["byte"] for g in font["glyphs"]], list(range(256)))
            self.assertEqual([g["byte"] for g in font["glyphs"] if g["status"] == "missing"],
                             [2, 8, 10] if height == "8" else [])
            self.assertFalse(any(g["status"] in ("clipped", "unexpected-blank")
                                 for g in font["glyphs"]))

    def test_retained_review_is_reproducible(self):
        for name, content in self.outputs.items():
            self.assertEqual((LOCALE / "review" / name).read_bytes(), content, name)

    def test_mapping_and_source_corruption_are_rejected(self):
        with tempfile.TemporaryDirectory(prefix="baltic-font-sources-") as work:
            directory = Path(work) / "baltic"
            shutil.copytree(LOCALE, directory)
            # Share only read-only source inputs; mutations stay in this copy.
            (Path(work) / "ru").symlink_to(ROOT / "locales/ru", target_is_directory=True)
            path = directory / "manifest.json"
            original = path.read_text()
            manifest = json.loads(original)
            manifest["unicode_mapping"][0xe4] = ord("o")
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "published CP775"):
                fonts.audit(directory)
            manifest = json.loads(original)
            manifest["display_mapping"][0xb5] = 0x2561
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "printable slot"):
                fonts.audit(directory)
            path.write_text(original)
            mapping = directory / "upstream/CP775.TXT"
            mapping.write_bytes(mapping.read_bytes() + b"\n# corrupt\n")
            with self.assertRaisesRegex(ValueError, "source hash mismatch"):
                fonts.audit(directory)


if __name__ == "__main__":
    unittest.main()
