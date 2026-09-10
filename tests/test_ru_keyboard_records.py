#!/usr/bin/env python3
"""Validate Russian records in the supplemental library against independently captured DOS tables.

This gate proves the file format and data, not resident modifier behavior.
"""
import importlib.util
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest

from baltic_keyboard_records import validate as validate_library

ROOT = Path(__file__).resolve().parents[1]
KEYBOARD = ROOT / 'src/DEV/KEYBOARD/KEYBRD2.SYS'
spec = importlib.util.spec_from_file_location('capture', ROOT / 'tools/capture_ru_contract.py')
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)
REFERENCE = json.loads((ROOT / 'locales/ru/dos622-reference.json').read_text())['keyboard']


def validate(path):
    data = path.read_bytes()
    begin, _, end = validate_library(data)['RU']
    if hashlib.sha256(data[begin:end]).hexdigest() != 'dba69ef0499cd9dccc96d13d54a933d3e57ce99ee59b6bfc347ef042dcff9255':
        # Includes state logic, common header and complete CP866 page.
        # Frozen from the standalone pre-Baltic library, not regenerated here.
        raise ValueError('Russian logic or translation mismatch')
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
