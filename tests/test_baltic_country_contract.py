#!/usr/bin/env python3
"""Verify the selected Baltic country expectations before driver integration."""

import importlib.util
import json
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("baltic_country", ROOT / "tools/baltic_country_contract.py")
country = importlib.util.module_from_spec(spec)
spec.loader.exec_module(country)


class BalticCountryContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.contract = json.loads((country.LOCALE / "country-contract.json").read_text())
        cls.output = country.materialize()
        cls.data = json.loads(cls.output)["countries"]

    def test_retained_expectations(self):
        self.assertEqual((country.LOCALE / "review/country-expectations.json").read_bytes(), self.output)
        self.assertEqual(set(self.data), {"et", "lv", "lt"})
        for pages in self.data.values():
            self.assertEqual(set(pages), {"775", "437", "850"})

    def test_pre_euro_format_fields(self):
        expected = {"et": (372, 1, b"KR\0\0\0", b" \0", 0),
                    "lv": (371, 2, b"Ls\0\0\0", b" \0", 3),
                    "lt": (370, 2, b"Lt\0\0\0", b".\0", 3)}
        for language, (number, order, symbol, thousands, style) in expected.items():
            for page, record in self.data[language].items():
                info = bytes.fromhex(record["country_info_hex"])
                self.assertEqual(len(info), 38)
                self.assertEqual(struct.unpack_from("<HHH", info), (number, int(page), order))
                self.assertEqual(info[6:11], symbol)
                self.assertEqual(info[11:19], thousands + b",\0.\0:\0")
                self.assertEqual(info[19:22], bytes([style, 2, 1]))
                self.assertEqual(info[22:], b"\0" * 4 + b";\0" + b"\0" * 10)

    def test_national_order_examples(self):
        # Fixed examples independent of the contract's full group sequences.
        orders = {"et": "S\u0160Z\u017dTUV\u00d5\u00c4\u00d6\u00dcXY",
                  "lv": "A\u0100C\u010cE\u0112G\u0122IY\u012aK\u0136L\u013bN\u0145S\u0160U\u016aZ\u017d",
                  "lt": "A\u0104C\u010cE\u0118\u0116I\u012eYJS\u0160U\u0172\u016aZ\u017d"}
        for language, text in orders.items():
            table = bytes.fromhex(self.data[language]["775"]["collation_hex"])
            encoded = text.encode("cp775")
            weights = [table[b] for b in encoded]
            self.assertEqual(weights, sorted(set(weights)), language)
            self.assertEqual([table[b] for b in text.lower().encode("cp775")], weights)
        # An unchanged CP775 number must not disguise a stale country table.
        self.assertEqual(len({self.data[x]["775"]["collation_hex"] for x in self.data}), 3)

    def test_uppercase_preserves_unrepresentable_partners(self):
        table = bytes.fromhex(self.data["et"]["775"]["uppercase_hex"])
        self.assertEqual(table[0xe4], 0xe5)  # Estonian o with tilde.
        self.assertEqual(table[0x85], 0x95)  # Latvian g with cedilla.
        self.assertEqual(table[0xd0], 0xb5)  # Lithuanian a with ogonek.
        self.assertEqual(table[0xe1], 0xe1)  # Sharp s must not expand to SS.
        self.assertEqual(table[0xe6], 0xe6)  # Micro sign: capital absent.
        for pages in self.data.values():
            for page, record in pages.items():
                upper = bytes.fromhex(record["uppercase_hex"])
                self.assertEqual(upper, bytes.fromhex(record["filename_uppercase_hex"]))
                self.assertEqual(bytes(upper[b] for b in upper), upper)
                self.assertEqual(upper[97:123], bytes(range(65, 91)))
                collate = bytes.fromhex(record["collation_hex"])
                self.assertEqual(len(collate), 256)
                self.assertEqual(bytes(collate[b] for b in upper), collate)

    def test_incomplete_or_ambiguous_letter_order_rejected(self):
        profile = dict(self.contract["profiles"]["et"])
        original = profile["collation_groups"]
        profile["collation_groups"] = original.replace("\u0160", "")
        with self.assertRaisesRegex(ValueError, "unassigned letter"):
            country.tables(profile, 775)
        profile["collation_groups"] = original + "A"
        with self.assertRaisesRegex(ValueError, "duplicate collation"):
            country.tables(profile, 775)


if __name__ == "__main__":
    unittest.main()
