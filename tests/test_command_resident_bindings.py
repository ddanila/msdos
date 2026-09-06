#!/usr/bin/env python3
"""Reject incomplete or misencoded development owner bindings."""
import unittest

from report_command_residency import (
    BINDING_SLOTS, check_resident_bindings, check_critical_owner_bindings,
)


class BindingTest(unittest.TestCase):
    def fixture(self):
        image = bytearray(1024)
        symbols = {"CONPROC": 0x300, "RES_CODE_END": 0x200}
        for index, name in enumerate(BINDING_SLOTS):
            offset = 0x110 + index * 4
            symbols["shell_binding_" + name] = offset
            image[offset-0x101] = 0xBB if name == "int2e_bx" else 0xB8
            start = 0x203 + index * 4
            image[start:start+4] = b"\x8c\x0e" + offset.to_bytes(2, "little")
        return symbols, image

    def test_complete(self):
        check_resident_bindings(*self.fixture())

    def test_missing_slot(self):
        symbols, image = self.fixture()
        del symbols["shell_binding_lodcom_ax"]
        with self.assertRaises(ValueError):
            check_resident_bindings(symbols, image)

    def test_bad_immediate(self):
        symbols, image = self.fixture()
        image[0x10] = 1
        with self.assertRaises(ValueError):
            check_resident_bindings(symbols, image)

    def test_bad_constructor(self):
        symbols, image = self.fixture()
        image[0x205] ^= 1
        with self.assertRaises(ValueError):
            check_resident_bindings(symbols, image)


class CriticalBindingTest(unittest.TestCase):
    def fixture(self):
        symbols = {"shell_binding_critical_es": 0x112,
                   "shell_binding_critical_ds": 0x132, "CDEVAT": 0x456}
        image = bytearray(128)
        image[0x10:0x1C] = b"\x50\xb8\0\0\x8e\xc0\x58\x26\x88\x26\x56\x04"
        image[0x30:0x37] = b"\x50\xb8\0\0\x8e\xd8\x58"
        return symbols, image

    def test_complete(self):
        check_critical_owner_bindings(*self.fixture())

    def test_wrong_data_owner_or_clobber(self):
        for offset, replacement in ((0x15, 0xD8), (0x17, 0x2E),
                                    (0x17, 0x3E), (0x16, 0x90),
                                    (0x35, 0xC0), (0x1A, 0)):
            with self.subTest(offset=offset, replacement=replacement):
                symbols, image = self.fixture()
                image[offset] = replacement
                with self.assertRaises(ValueError):
                    check_critical_owner_bindings(symbols, image)


if __name__ == "__main__":
    unittest.main()
