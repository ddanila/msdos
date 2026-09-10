#!/usr/bin/env python3
"""Invoke the separately licensed DOSEMU2 test dependency as a subprocess."""
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
runner = ROOT / 'dosemu2/test/qemu_dos.py'
if not runner.is_file():
    raise SystemExit('Initialize the pinned tests with: git submodule update --init dosemu2')
os.execv(sys.executable, [sys.executable, str(runner),
    '--boot-image', os.environ.get('FLOPPY_IMAGE', str(ROOT / 'out/floppy.img')),
    '--output', str(ROOT / 'out'), *sys.argv[1:]])
