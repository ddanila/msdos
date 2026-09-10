#!/usr/bin/env python3
"""Assemble the candidate library and reject malformed sections/allocations."""
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

from baltic_keyboard_records import validate
from test_ru_keyboard_records import capture, REFERENCE

ROOT = Path(__file__).resolve().parents[1]


class BalticKeyboardRecords(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='baltic-key-records-')
        cls.addClassCleanup(cls.directory.cleanup)
        work = Path(cls.directory.name)
        cls.path = work/'KEYBRD2.SYS'
        for source, output in [('KDFBALT.ASM', cls.path), ('KDFRU.ASM', work/'RU.SYS')]:
            subprocess.run([str(ROOT/'bin/jwasm-bin'), '-I../../INC', '-Fo'+str(output), source],
                           cwd=ROOT/'src/DEV/KEYBOARD', check=True)
        cls.data = cls.path.read_bytes()
        cls.russian = (work/'RU.SYS').read_bytes()

    def test_generated_source_current(self):
        subprocess.run(['python3', str(ROOT/'tools/build_baltic_keyboard.py'), '--check'], check=True)

    def test_library_and_russian_preservation(self):
        sections = validate(self.data)
        begin, _, end = sections['RU']
        old_entry = struct.unpack_from('<I', self.russian, 30)[0]
        old_logic = struct.unpack_from('<I', self.russian, old_entry+4)[0]
        self.assertEqual(self.data[begin:end], self.russian[old_logic:])
        _, actual = capture.keyboard_tables(self.path)
        self.assertEqual(actual['states'], REFERENCE['states'])

    def test_truncation_and_trailing_bytes(self):
        for data in (self.data[:-1], self.data+bytes(1)):
            with self.assertRaises(ValueError):
                validate(data)

    def test_bad_pointer_and_allocation(self):
        for offset, value, fmt in [(30, len(self.data)+1, '<I'), (18, 1, '<H'),
                                   (20, 1, '<H'), (26, 4, '<H')]:
            data = bytearray(self.data)
            struct.pack_into(fmt, data, offset, value)
            with self.assertRaises(ValueError):
                validate(data)

    def test_dead_state_wrong_section_and_count(self):
        logic, _, _ = validate(self.data)['ET']
        common = logic + struct.unpack_from('<H', self.data, logic)[0]
        for offset in (common+2, common+4+7):
            data = bytearray(self.data)
            data[offset] ^= 1
            with self.assertRaises(ValueError):
                validate(data)


if __name__ == '__main__':
    unittest.main()
