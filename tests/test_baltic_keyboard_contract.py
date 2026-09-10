#!/usr/bin/env python3
"""Check captured Baltic input facts independently of driver generation."""

import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("baltic_keys", ROOT / "tools/capture_baltic_keyboard.py")
keys = importlib.util.module_from_spec(spec)
spec.loader.exec_module(keys)


class BalticKeyboardContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.output = keys.materialize()
        cls.profiles = json.loads(cls.output)["profiles"]

    def test_retained_capture(self):
        self.assertEqual((keys.LOCALE / "review/keyboard-expectations.json").read_bytes(), self.output)
        self.assertEqual(set(self.profiles), {"et", "lv", "lt"})

    def test_independent_national_key_positions(self):
        # Fixed physical scan/plane/byte facts from the selected KEY layouts.
        for lang, scan, plane, byte in [
                ("et", 27, 0, 0xe4), ("et", 27, 1, 0xe5),
                ("et", 31, 2, 0xd5), ("et", 44, 3, 0xcf),
                ("lv", 34, 2, 0x85), ("lv", 34, 3, 0x95),
                ("lt", 16, 0, 0xd0), ("lt", 16, 1, 0xb5)]:
            item = self.profiles[lang]["keys"][str(scan)][plane]
            self.assertEqual((item["kind"], item["byte"], item["scan"]),
                             ("character", byte, scan))
        # Lithuanian LST 1582 moves Q/W/X/F and their BIOS scan codes.
        item = self.profiles["lt"]["keys"]["13"][0]
        self.assertEqual((item["byte"], item["scan"]), (ord("x"), 45))
        item = self.profiles["lt"]["keys"]["43"][3]
        self.assertEqual((item["byte"], item["scan"]), (17, 16))

    def test_required_letters_reachable(self):
        manifest = json.loads((keys.LOCALE / "manifest.json").read_text())
        for lang, profile in self.profiles.items():
            direct = {item["byte"] for row in profile["keys"].values()
                      for item in row if item and item["kind"] == "character"}
            composed = {b for table in profile["dead_keys"].values() for b in table["pairs"].values()}
            language = manifest["languages"][lang]
            required = (language["required_lowercase"] + language["required_uppercase"]).encode("cp775")
            self.assertTrue(set(required) <= direct | composed, lang)

    def test_composition_and_literal_facts(self):
        estonian = self.profiles["et"]["dead_keys"]
        self.assertEqual(estonian["2"]["pairs"][str(ord("o"))], 0xe4)
        self.assertEqual(estonian["2"]["pairs"][str(ord("O"))], 0xe5)
        latvian = self.profiles["lv"]["dead_keys"]
        self.assertEqual(latvian["1"]["pairs"][str(ord("a"))], 0x86)
        self.assertEqual(latvian["1"]["pairs"][str(ord("A"))], 0x8f)
        for profile in self.profiles.values():
            for table in profile["dead_keys"].values():
                self.assertEqual(table["pairs"]["32"], table["literal"])
        self.assertEqual(self.profiles["lt"]["dead_keys"], {})

    def test_byte_whitespace_and_layer_fallback(self):
        # 85 and A0 are letters in CP775, not Unicode NEL/NBSP delimiters.
        data = (b"[KEYS:common]\n34C g G\n[KEYS:specific]\n34C !0 !0 \x85 \xa0\n"
                b"[PLANES]\nAltGr | Shift\nShift AltGr\n"
                b"[SUBMAPPINGS]\n0 common\n775 specific\n[GENERAL]\nName=,ZZ\n")
        profile = keys.capture(data)
        row = profile["keys"]["34"]
        self.assertEqual([x["byte"] for x in row], [103, 71, 0x85, 0xa0])
        self.assertTrue(all(x["caps"] for x in row))

    def test_unknown_syntax_and_commands_rejected(self):
        with self.assertRaisesRegex(ValueError, "unsupported reference command"):
            keys.effect("!161", 1, False)
        with self.assertRaisesRegex(ValueError, "trailing character"):
            keys.effect("ab", 1, False)
        with self.assertRaisesRegex(ValueError, "duplicate physical"):
            keys.key_rows([["1", "a"], ["1", "b"]])
        self.assertEqual(keys.effect("131/#0", 13, True),
                         {"kind": "character", "scan": 131, "byte": 0})


if __name__ == "__main__":
    unittest.main()
