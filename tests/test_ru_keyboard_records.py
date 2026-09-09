#!/usr/bin/env python3
"""Validate the RU-only library against independently captured DOS tables.

This gate proves the file format and data, not resident modifier behavior.
"""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
KEYBOARD = ROOT / 'src/DEV/KEYBOARD/KEYBRD2.SYS'
spec = importlib.util.spec_from_file_location('capture', ROOT / 'tools/capture_ru_contract.py')
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)
REFERENCE = json.loads((ROOT / 'locales/ru/dos622-reference.json').read_text())['keyboard']


def validate(path):
    data = path.read_bytes()
    reader = capture.Reader(path)
    if reader.take(0, 16) != b'\xffKEYB   ' + bytes(8):
        raise ValueError('signature/reserved bytes')
    if reader.take(22, 6) != struct.pack('<HHH', 0, 1, 1):
        raise ValueError('RU-only counts')
    entry = reader.pointer(30)
    if reader.word(34) != 441 or reader.pointer(36) != entry:
        raise ValueError('identifier directory')
    if reader.take(entry + 8, 2) != b'\x01\x01':
        raise ValueError('one identifier and one code page required')
    logic = reader.pointer(entry + 4)
    common = logic + reader.word(logic)
    page = reader.pointer(entry + 12)
    if reader.take(common, 6) != struct.pack('<HHH', 6, 65535, 0):
        raise ValueError('empty common section')
    if page != common + 6 or page + reader.word(page) != len(data):
        raise ValueError('section boundaries')
    if reader.take(16, 6) != struct.pack('<HHH', 1120, 496, 640):
        raise ValueError('allocation bounds')
    if reader.word(page) > 496 or reader.word(logic) > 640:
        raise ValueError('section exceeds allocation')
    _, actual = capture.keyboard_tables(path)
    if actual['identifier'] != 441:
        raise ValueError('RU identifier')
    for key in ('3', '4', '5', '6', '7'):
        state, expected = actual['states'][key], REFERENCE['states'][key]
        if state['keyboard_mask'] != expected['keyboard_mask']:
            raise ValueError('keyboard variants')
        ordered = lambda entries: sorted(entries, key=lambda entry: entry['scan'])
        if ordered(state['translations']) != ordered(expected['translations']):
            raise ValueError('key translation mismatch')


class RussianKeyboardRecords(unittest.TestCase):
    def test_complete_library(self):
        validate(KEYBOARD)

    def test_corrupt_translation_detected(self):
        data = bytearray(KEYBOARD.read_bytes())
        # Explicit Yo scan/lowercase pair, independently fixed by the contract.
        position = data.index(b'\x29\xf1')
        data[position + 1] = 0xf0
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'KEYBRD2.SYS'
            path.write_bytes(data)
            with self.assertRaisesRegex(ValueError, 'translation mismatch'):
                validate(path)

    def test_invalid_pointer_detected(self):
        data = bytearray(KEYBOARD.read_bytes())
        struct.pack_into('<I', data, 30, len(data) + 1)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'KEYBRD2.SYS'
            path.write_bytes(data)
            with self.assertRaises(ValueError):
                validate(path)

    def test_short_record_detected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'KEYBRD2.SYS'
            path.write_bytes(KEYBOARD.read_bytes()[:-1])
            with self.assertRaises(ValueError):
                validate(path)


if __name__ == '__main__':
    unittest.main()
