#!/usr/bin/env python3
"""Validate register capture without assigning meaning to failure pointers."""
import unittest

from capture_opendos_sda import parse_registers


class SdaCaptureTests(unittest.TestCase):
    sample = ("SDA_5D06 CF AX DS SI CX DX: 0000 5D06 0100 0320 078C 001A \r\n"
              "SDA_5D0B CF AX DS SI CX DX: 0001 0001 034F 0000 0000 01A4 \r\n")

    def test_success_and_unsupported_are_distinct(self):
        rows = parse_registers(self.sample)
        self.assertEqual(rows["5D06"], dict(cf=0, ax=0x5D06, ds=0x100,
                                           si=0x320, cx=1932, dx=26))
        self.assertEqual(rows["5D0B"]["cf"], 1)
        self.assertEqual(rows["5D0B"]["ax"], 1)

    def test_missing_or_malformed(self):
        for text in ("", self.sample.splitlines()[0],
                     self.sample.replace("078C", "????")):
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_registers(text)

    def test_duplicate(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            parse_registers(self.sample + self.sample)

    def test_invalid_flag(self):
        with self.assertRaisesRegex(ValueError, "carry"):
            parse_registers(self.sample.replace("0000 5D06", "0002 5D06"))


if __name__ == "__main__":
    unittest.main()
