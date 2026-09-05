#!/usr/bin/env python3
"""Prove the source-linked kernel entry jump and HMA address bias."""

from __future__ import annotations

import re
import shutil
import struct
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DOS = ROOT / "src/DOS"


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
    data_version = map_offset(kernel_map, "DataVersion") - group_base(kernel_map)
    assert data_version == 0x14, (
        f"kernel HMA bias places DataVersion at {data_version:04x}, expected 0014"
    )

    low_end = map_offset(kernel_map, "DOS_LOW_GATE_END")
    sysbuf = map_offset(kernel_map, "SYSBUF")
    error_start = map_offset(kernel_map, "I21_MAP_E_TAB")
    error_end = map_offset(kernel_map, "ErrMap24End")
    assert low_end <= error_start < error_end <= sysbuf, (
        "private error metadata must be reclaimed low and retained in the HMA copy"
    )
    assert error_end - error_start == 403, "private error metadata coverage changed"
    curadd = map_offset(kernel_map, "CURADD")
    assert low_end < curadd < sysbuf, "CURADD is not in the relocated DOS tail"
    address = struct.pack("<H", curadd)
    expected = (
        b"\x2e\xa3" + address,       # mov cs:[CURADD],ax
        b"\x2e\xa1" + address,       # mov ax,cs:[CURADD]
        b"\x2e\x89\x3e" + address,  # mov cs:[CURADD],di
    )
    for encoding in expected:
        assert encoding in kernel, f"missing CS-relative CURADD access {encoding.hex()}"
    forbidden = (
        b"\x36\xa3" + address,
        b"\x36\xa1" + address,
        b"\x36\x89\x3e" + address,
    )
    for encoding in forbidden:
        assert encoding not in kernel, (
            f"SS-relative CURADD access can overwrite released DOS memory: {encoding.hex()}"
        )

    ndisasm = shutil.which("ndisasm")
    assert ndisasm, "ndisasm is required for the relocated-tail addressing check"
    disassembly = subprocess.check_output(
        [ndisasm, "-b", "16", "-e", str(low_end), "-o", str(low_end), str(DOS / "MSDOS.SYS")],
        text=True,
    )
    stale_ss: list[str] = []
    for line in disassembly.splitlines():
        fields = line.split(maxsplit=2)
        if not fields or int(fields[0], 16) >= sysbuf:
            break
        for target in re.findall(r"\[ss:0x([0-9a-f]+)", line, re.I):
            if int(target, 16) >= low_end:
                stale_ss.append(line)
    assert not stale_ss, (
        "relocated DOS code addresses released tail storage through SS:\n"
        + "\n".join(stale_ss)
    )

    share_map = ROOT / "src/CMD/SHARE/share.map"
    assert map_offset(share_map, "DataVersion") - group_base(share_map) == data_version, (
        "SHARE and the kernel disagree on the replicated DOSGROUP layout"
    )
    print("kernel entry and relocated-tail layout tests passed")


if __name__ == "__main__":
    main()
