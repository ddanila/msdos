"""Resolve an explicitly selected, hash-checked production memory core."""
import hashlib
import json
import os
from pathlib import Path


def selected_core():
    value = os.environ.get('MEMORY_CORE_DIR')
    if not value:
        return {}
    directory = Path(value).resolve()
    record = json.loads((directory.parent/'build.json').read_text())
    assert record['kind']=='memory-production-build'
    expected = {'IO.SYS','MSDOS.SYS','COMMAND.COM','HIMEM.SYS','EMM386.EXE'}
    assert set(record['sha256'])==expected
    files = {name:(directory/name).read_bytes() for name in expected}
    for name,data in files.items():
        assert hashlib.sha256(data).hexdigest()==record['sha256'][name], name
    return files
