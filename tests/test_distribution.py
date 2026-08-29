#!/usr/bin/env python3
"""Validate deterministic DOS 5 compressed installation media."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import struct
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "tools" / "build_distribution.py"
FILES = json.loads((ROOT / "distribution" / "files.json").read_text())
spec = importlib.util.spec_from_file_location("szdd", ROOT / "tools" / "szdd.py")
szdd = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(szdd)


def root_files(image: bytes) -> dict[str, bytes]:
    result = {}
    root_start = 19 * 512
    data_start = 33 * 512
    fat = image[512:10 * 512]

    def fat12(cluster: int) -> int:
        offset = cluster + cluster // 2
        word = struct.unpack_from("<H", fat, offset)[0]
        return (word >> 4) & 0xFFF if cluster & 1 else word & 0xFFF

    for index in range(224):
        entry = image[root_start + index * 32:root_start + (index + 1) * 32]
        if not entry or entry[0] == 0:
            break
        if entry[11] & 0x08:
            continue
        stem = entry[:8].decode("ascii").rstrip()
        extension = entry[8:11].decode("ascii").rstrip()
        name = stem + (("." + extension) if extension else "")
        size = struct.unpack_from("<I", entry, 28)[0]
        cluster = struct.unpack_from("<H", entry, 26)[0]
        data = bytearray()
        seen = set()
        while 2 <= cluster < 0xFF8 and cluster not in seen:
            seen.add(cluster)
            start = data_start + (cluster - 2) * 512
            data += image[start:start + 512]
            cluster = fat12(cluster)
        result[name] = bytes(data[:size])
    return result


with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
    subprocess.run(["python3", str(BUILD), "--output", first], cwd=ROOT, check=True)
    subprocess.run(["python3", str(BUILD), "--output", second], cwd=ROOT, check=True)
    for name in ("disk1.img", "disk2.img", "manifest.json"):
        assert (Path(first) / name).read_bytes() == (Path(second) / name).read_bytes()
    disk1 = (Path(first) / "disk1.img").read_bytes()
    disk2 = (Path(first) / "disk2.img").read_bytes()

assert len(disk1) == len(disk2) == 1_474_560
assert disk1[510:512] == disk2[510:512] == b"\x55\xaa"
files1, files2 = root_files(disk1), root_files(disk2)
assert list(files1)[:2] == ["IO.SYS", "MSDOS.SYS"]
assert "PACKING.LST" in files1 and files1["PACKING.LST"] == files2["PACKING.LST"]
for relative, destination in FILES["boot"]:
    assert files1[destination] == (ROOT / relative).read_bytes()
for relative, destination in FILES["compressed"]:
    stem, dot, extension = destination.partition(".")
    packed_name = stem + "." + extension[:-1] + "_" if dot else stem[:-1] + "_"
    decoded, missing = szdd.decode(files2[packed_name])
    assert decoded == (ROOT / relative).read_bytes()
    assert chr(missing) == destination[-1]
print(
    f"distribution media passed: {len(files1)} boot files, {len(files2) - 1} compressed files; "
    f"disk hashes {hashlib.sha256(disk1).hexdigest()[:12]} {hashlib.sha256(disk2).hexdigest()[:12]}"
)
