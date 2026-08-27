#!/usr/bin/env python3
"""Prove the unpatched kernel entry jump is produced by linker layout."""

from __future__ import annotations

import re
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DOS = ROOT / "MS-DOS/v4.0/src/DOS"


def map_offset(map_file: Path, symbol: str) -> int:
    pattern = re.compile(rf"^([0-9a-f]{{4}}):([0-9a-f]{{4}})\*?\s+{symbol}$", re.I)
    for line in map_file.read_text(encoding="latin-1").splitlines():
        match = pattern.match(line.strip())
        if match:
            segment, offset = (int(value, 16) for value in match.groups())
            return segment * 16 + offset
    raise AssertionError(f"{symbol} is absent from {map_file.name}")


def group_base(map_file: Path) -> int:
    pattern = re.compile(r"^DOSGROUP\s+([0-9a-f]{4}):([0-9a-f]{4})", re.I)
    for line in map_file.read_text(encoding="latin-1").splitlines():
        match = pattern.match(line.strip())
        if match:
            segment, offset = (int(value, 16) for value in match.groups())
            return segment * 16 + offset
    raise AssertionError(f"DOSGROUP is absent from {map_file.name}")


def main() -> None:
    kernel = (DOS / "MSDOS.SYS").read_bytes()
    assert kernel[0] == 0xE9, "MSDOS.SYS does not begin with the source near JMP"
    displacement = struct.unpack_from("<h", kernel, 1)[0]
    target = (3 + displacement) & 0xFFFF
    kernel_map = DOS / "MSDOS.MAP"
    dosinit = map_offset(kernel_map, "DOSINIT")
    assert target == dosinit, (
        f"entry JMP targets {target:04x}, but the map places DOSINIT at {dosinit:04x}"
    )
    assert map_offset(kernel_map, "DataVersion") - group_base(kernel_map) == 4

    share_map = ROOT / "MS-DOS/v4.0/src/CMD/SHARE/SHARE.MAP"
    assert map_offset(share_map, "DataVersion") - group_base(share_map) == 4, (
        "SHARE and the kernel disagree on the replicated DOSGROUP layout"
    )
    print("unpatched kernel entry layout test passed")


if __name__ == "__main__":
    main()
