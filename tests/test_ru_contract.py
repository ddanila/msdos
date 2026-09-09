#!/usr/bin/env python3
"""Validate the independent Russian DOS country/keyboard expectations."""

import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
LOCALE = ROOT / "locales/ru"


class RussianContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reference = json.loads((LOCALE / "dos622-reference.json").read_text())
        cls.contract = json.loads((LOCALE / "manifest.json").read_text())["behavior"]

    def test_reference_identity(self):
        self.assertEqual(hashlib.sha256((LOCALE / "dos622-reference.json").read_bytes()).hexdigest(),
                         self.contract["reference_sha256"])
        self.assertEqual(self.reference["sources"][0]["sha256"],
                         "59362ad35595e7f830ee8a2db3e6ec2fa0e5e479411be409b530131bb1b1b3b9")
        self.assertEqual(self.reference["sources"][1]["sha256"],
                         "da925ca6ed4741df02e82bf618b3b98dd5bfd72788485b5fa639c7b5f8a20327")

    def test_formats(self):
        for page, record in self.reference["country_records"].items():
            data = bytes.fromhex(record["objects"]["1"]["payload"])
            self.assertEqual(int.from_bytes(data[:2], "little"), 7)
            self.assertEqual(int.from_bytes(data[2:4], "little"), int(page))
            self.assertEqual(data[4:6], b"\x01\x00")  # day/month/year
            self.assertEqual(data[6:11], (b"\xe0." if page == "866" else b"r.") + bytes(3))
            self.assertEqual(data[11:19], b" \0.\0.\0:\0")
            self.assertEqual(data[19:22], b"\x03\x02\x01")  # after/space, cents, 24h
            self.assertEqual(data[26:28], b";\0")

    def test_case_and_collation_are_separate(self):
        objects = self.reference["country_records"]["866"]["objects"]
        upper = bytes.fromhex(objects["2"]["payload"])
        self.assertEqual(upper, bytes.fromhex(objects["4"]["payload"]))
        for byte in range(128, 256):
            letter = bytes([byte]).decode("cp866")
            self.assertEqual(upper[byte - 128], letter.upper().encode("cp866")[0])
        collate = bytes.fromhex(objects["6"]["payload"])
        self.assertEqual(len(collate), 256)
        # The retail sort order is lower then upper, including Yo after Ie.
        for lower, upper_byte in enumerate(upper, 128):
            if lower != upper_byte:
                self.assertLess(collate[lower], collate[upper_byte])
        self.assertLess(collate[0x85], collate[0xf1])
        self.assertLess(collate[0xf0], collate[0xa6])
        self.assertEqual(set(collate[0xb0:0xe0]), {240})

    def test_keyboard_alphabet_and_punctuation(self):
        keyboard = self.reference["keyboard"]
        self.assertEqual(keyboard["identifier"], 441)
        states = {key: {item["scan"]: item for item in state["translations"]}
                  for key, state in keyboard["states"].items()}
        # Unicode codepoints for JCUKEN rows, specified separately from tables.
        rows = {
            0x10: [0x439, 0x446, 0x443, 0x43a, 0x435, 0x43d, 0x433, 0x448, 0x449, 0x437, 0x445, 0x44a],
            0x1e: [0x444, 0x44b, 0x432, 0x430, 0x43f, 0x440, 0x43e, 0x43b, 0x434, 0x436, 0x44d],
            0x2c: [0x44f, 0x447, 0x441, 0x43c, 0x438, 0x442, 0x44c, 0x431, 0x44e],
            0x29: [0x451],
        }
        for first, letters in rows.items():
            for scan, code in enumerate(letters, first):
                lower = states["3"][scan]
                upper = states["4"][scan]
                self.assertEqual(lower["byte"], chr(code).encode("cp866")[0])
                self.assertEqual(upper["byte"], chr(code).upper().encode("cp866")[0])
                self.assertEqual((lower["bios_scan"], upper["bios_scan"]), (0, 0))
        self.assertEqual(states["5"][0x35]["byte"], ord("."))
        self.assertEqual(states["6"][0x35]["byte"], ord(","))
        self.assertEqual(states["6"][0x04]["byte"], 0xfc)  # numero sign
        self.assertEqual(states["6"][0x05]["byte"], ord(";"))


if __name__ == "__main__":
    unittest.main()
