#!/usr/bin/env python3
"""Exercise the deterministic host SZDD codec."""

import hashlib
import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("szdd", ROOT / "tools" / "szdd.py")
szdd = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(szdd)


cases = [
    b"",
    b" ",
    b" " * 8192,
    bytes(range(256)) * 300,
    (b"DOS 5 deterministic compression\r\n" * 4096) + bytes(range(256)),
]
for payload in cases:
    first = szdd.encode(payload, ord("T"))
    second = szdd.encode(payload, ord("T"))
    assert first == second
    decoded, missing = szdd.decode(first)
    assert decoded == payload
    assert missing == ord("T")

compressible = cases[-1]
encoded = szdd.encode(compressible)
assert len(encoded) < len(compressible) // 4
print(
    "SZDD host codec passed 5 deterministic round trips; sample sha256="
    + hashlib.sha256(encoded).hexdigest()
)
