#!/usr/bin/env python3
"""Reject incomplete or misencoded development owner bindings."""
import unittest

from report_command_residency import BINDING_SLOTS, check_resident_bindings


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


if __name__ == "__main__":
    unittest.main()
