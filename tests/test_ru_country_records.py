#!/usr/bin/env python3
"""Check Russian COUNTRY.SYS records and preservation of every prior record."""

import hashlib
import json
from pathlib import Path
import unittest

from country_records import read_records

ROOT = Path(__file__).resolve().parents[1]
COUNTRY = ROOT / "src/DEV/COUNTRY/COUNTRY.SYS"
LOCALE = ROOT / "locales/ru"


def check_russian(records):
    reference = json.loads((LOCALE / "dos622-reference.json").read_text())["country_records"]
    for page in (866, 437, 850):
        objects = records[7, page]
        assert set(objects) == {1, 2, 4, 5, 6, 7}
        for kind, actual in objects.items():
            source = reference[str(page)]["objects"]
            # Retail 866 omits FILELIST; expose the shared RU/437 rules.
            expected = source.get(str(kind), reference["437"]["objects"][str(kind)])
            assert actual["signature"].hex() == expected["signature"], (page, kind)
            assert actual["payload"].hex() == expected["payload"], (page, kind)


class RussianCountryRecords(unittest.TestCase):
    def test_russian_records_match_independent_reference(self):
        check_russian(read_records(COUNTRY.read_bytes()))

    def test_every_prior_record_is_unchanged(self):
        expected = json.loads((LOCALE / "prior-country-records.json").read_text())["records"]
        actual = {
            f"{country}/{page}": {str(kind): hashlib.sha256(obj["signature"] + obj["payload"]).hexdigest()
                                  for kind, obj in objects.items()}
            for (country, page), objects in read_records(COUNTRY.read_bytes()).items()
            if country not in (7, 370, 371, 372)
        }
        self.assertEqual(actual, expected)

    def test_wrong_case_entry_is_detected(self):
        data = bytearray(COUNTRY.read_bytes())
        obj = read_records(data)[7, 866][2]
        data[obj["offset"] + 10 + (0xf1 - 128)] = 0xf1
        with self.assertRaises(AssertionError):
            check_russian(read_records(data))

    def test_invalid_object_pointer_is_rejected(self):
        data = bytearray(COUNTRY.read_bytes())
        data[35:39] = b"\xff" * 4  # first country record pointer
        with self.assertRaises(ValueError):
            read_records(data)


if __name__ == "__main__":
    unittest.main()
