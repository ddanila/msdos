#!/usr/bin/env python3
"""Guard comparison exceptions and legacy archive extraction boundaries."""
import io
from pathlib import Path
import tempfile
import unittest
import zipfile

from capture_dos_app_smoke import normalize, unzip


class SmokeHelpers(unittest.TestCase):
    def test_debugger_relocation_preserves_relationships(self):
        stock = 'CS 1234 DS 1234 ES 1234 SS 1234 DX 1234 BP 0000'
        fork = 'CS 4321 DS 4321 ES 4321 SS 4321 DX 4321 BP 0000'
        self.assertEqual(normalize('d86', stock), normalize('d86', fork))
        self.assertNotEqual(normalize('d86', stock),
                            normalize('d86', fork.replace('DS 4321', 'DS 4322')))
        self.assertNotEqual(normalize('d86', stock),
                            normalize('d86', fork.replace('BP 0000', 'BP 0001')))

    def test_memory_exception_preserves_operational_status(self):
        stock = 'Memory in use           374 Kb; Add to archive Enabled'
        fork = stock.replace('374', '369')
        self.assertEqual(normalize('rar', stock), normalize('rar', fork))
        self.assertNotEqual(normalize('rar', stock),
                            normalize('rar', fork.replace('Enabled', 'Disabled')))
        self.assertNotEqual(normalize('hiew', stock), normalize('hiew', fork))

    def test_spreadsheet_exception_preserves_usage_and_cells(self):
        stock = 'A1: 42\nV57 Free:100%[202k] READY! 12:00:12 pm'
        fork = stock.replace('202k', '197k').replace('12:00:12', '12:00:14')
        self.assertEqual(normalize('asa57', stock), normalize('asa57', fork))
        for altered in (fork.replace('42', '43'), fork.replace('100%', '99%')):
            self.assertNotEqual(normalize('asa57', stock), normalize('asa57', altered))

    def test_archive_boundaries(self):
        for name, symlink in (('../escape', False), ('/escape', False), ('link', True)):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                data = io.BytesIO()
                with zipfile.ZipFile(data, 'w') as archive:
                    info = zipfile.ZipInfo(name)
                    if symlink:
                        info.create_system = 3
                        info.external_attr = 0o120777 << 16
                    archive.writestr(info, b'payload')
                data.seek(0)
                with zipfile.ZipFile(data) as archive, self.assertRaises(ValueError):
                    unzip(archive, Path(directory))


if __name__ == '__main__':
    unittest.main()
