#!/usr/bin/env python3
"""Validate Baltic COUNTRY.SYS data and preserve all pre-Baltic records."""

import hashlib
import json
from pathlib import Path
import unittest

from country_records import read_records

ROOT = Path(__file__).resolve().parents[1]
LOCALE = ROOT / "locales/baltic"
COUNTRY = ROOT / "src/DEV/COUNTRY/COUNTRY.SYS"


def check_baltic(data):
    records = read_records(data)
    expected = json.loads((LOCALE / "review/country-expectations.json").read_text())["countries"]
    for language, number in (("et", 372), ("lv", 371), ("lt", 370)):
        for page in (775, 437, 850):
            objects = records[number, page]
            reference = expected[language][str(page)]
            assert set(objects) == {1, 2, 4, 5, 6, 7}
            for kind, field, signature in (
                    (1, "country_info_hex", b"\xffCTYINFO"),
                    (2, "uppercase_hex", b"\xffUCASE  "),
                    (4, "filename_uppercase_hex", b"\xffUCASE  "),
                    (6, "collation_hex", b"\xffCOLLATE")):
                payload = bytes.fromhex(reference[field])
                if kind in (2, 4):
                    payload = payload[128:]
                assert objects[kind]["signature"] == signature, (language, page, kind)
                assert objects[kind]["payload"] == payload, (language, page, kind)
            for kind in (5, 7):
                for field in ("signature", "payload"):
                    assert objects[kind][field] == records[1, 437][kind][field]
    return records


class BalticCountryRecords(unittest.TestCase):
    def test_all_new_records(self):
        check_baltic(COUNTRY.read_bytes())

    def test_all_existing_record_contents_preserved(self):
        records = read_records(COUNTRY.read_bytes())
        old = json.loads((LOCALE / "prior-country-records.json").read_text())["records"]
        new = {f"{number}/{page}" for number in (370, 371, 372) for page in (775, 437, 850)}
        current = {f"{number}/{page}": {str(kind): hashlib.sha256(obj["signature"] + obj["payload"]).hexdigest()
                                      for kind, obj in objects.items()}
                   for (number, page), objects in records.items()}
        self.assertEqual(set(current), set(old) | new)
        self.assertEqual({key: current[key] for key in old}, old)
        # Default country selection follows the first record for that country.
        for number in (370, 371, 372):
            self.assertEqual(next(page for country, page in records if country == number), 775)

    def test_case_and_collation_corruption_detected(self):
        original = COUNTRY.read_bytes()
        for kind, index in ((2, 0xe4 - 128), (6, 0xe4)):
            data = bytearray(original)
            obj = read_records(data)[372, 775][kind]
            data[obj["offset"] + 10 + index] ^= 1
            with self.assertRaises(AssertionError):
                check_baltic(data)


if __name__ == "__main__":
    unittest.main()
