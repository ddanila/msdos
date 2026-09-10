"""Shared configuration and runtime evidence for Russian production-profile tests."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

CONFIG = {
    'high': 'DEVICE=HIMEM.SYS\r\nDEVICE=EMM386.EXE NOEMS\r\nDOS=HIGH,UMB\r\n',
    'low': 'DOS=LOW\r\n',
}


def verify_base(image):
    directory = os.environ.get('MEMORY_CORE_DIR')
    if not directory:
        raise SystemExit('Run make test-ru-profiles-qemu to select the production core.')
    expected = json.loads((Path(directory).parent/'build.json').read_text())['sha256']
    for name, digest in expected.items():
        data = subprocess.check_output(['mtype','-i',str(image),'::'+name])
        if hashlib.sha256(data).hexdigest() != digest:
            raise AssertionError('base image production-core mismatch: '+name)
    return expected


def require_profile(output, profile):
    marker = b'RU_HIGH_UMB_PASS' if profile == 'high' else b'RU_LOW_PASS'
    if marker not in output:
        raise AssertionError('missing runtime memory-profile proof: '+profile)
