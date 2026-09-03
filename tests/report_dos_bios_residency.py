#!/usr/bin/env python3
"""Report DOS-high and BIOS resident/discardable linker boundaries."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re


SEGMENT_RE = re.compile(
    r"^(\S+)\s+.*?([0-9A-F]{4}):([0-9A-F]{4})\s+([0-9A-F]{8})$",
    re.IGNORECASE,
)
SYMBOL_RE = re.compile(
    r"^([0-9A-F]{4}):([0-9A-F]{4})(?:[*+])?\s+(\S.*)$",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Segment:
    name: str
    paragraph: int
    offset: int
    size: int


def parse_map(path: Path) -> tuple[dict[str, Segment], dict[str, int]]:
    segments: dict[str, Segment] = {}
    symbols: dict[str, int] = {}
    section = ""
    for raw in path.read_text(encoding="latin-1").splitlines():
        if "|   Segments   |" in raw:
            section = "segments"
            continue
        if "|   Absolute Segments   |" in raw:
            section = "absolute"
            continue
        if "|   Memory Map   |" in raw:
            section = "symbols"
            continue
        if section == "segments":
            match = SEGMENT_RE.match(raw)
            if match:
                name, paragraph, offset, size = match.groups()
                segments[name] = Segment(
                    name, int(paragraph, 16), int(offset, 16), int(size, 16)
                )
        elif section == "symbols":
            match = SYMBOL_RE.match(raw)
            if match:
                paragraph, offset, name = match.groups()
                symbols.setdefault(name, int(paragraph, 16) * 16 + int(offset, 16))
    if not segments or not symbols:
        raise ValueError(f"could not parse segments and symbols from {path}")
    return segments, symbols


def rounded(value: int) -> int:
    return (value + 15) & ~15


def require(symbols: dict[str, int], name: str) -> int:
    try:
        return symbols[name]
    except KeyError as error:
        raise ValueError(f"required linker symbol {name!r} is missing") from error


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("dos_map", type=Path)
    parser.add_argument("bios_map", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    dos_segments, dos_symbols = parse_map(args.dos_map)
    bios_segments, bios_symbols = parse_map(args.bios_map)
    low_gate = require(dos_symbols, "DOS_LOW_GATE_END")
    sysbuf = require(dos_symbols, "SYSBUF")
    dos_last = dos_segments["LAST"]
    bios_code = bios_segments["CODE"]
    bios_init = bios_segments["SYSINITSEG"]
    bios_boundaries = [
        (name, require(bios_symbols, name))
        for name in ("ENDFLOPPY", "ENDONEHARD", "ENDTWOHARD", "END96TPI", "ENDATROM", "ENDK09")
    ]

    errors: list[str] = []
    if low_gate >= sysbuf:
        errors.append("DOS low gateway does not precede SYSBUF")
    if dos_last.paragraph * 16 != sysbuf:
        errors.append("DOS LAST segment no longer begins at SYSBUF")
    if any(left[1] >= right[1] for left, right in zip(bios_boundaries, bios_boundaries[1:])):
        errors.append("BIOS selectable resident boundaries are not ordered")
    if bios_boundaries[-1][1] > bios_code.size:
        errors.append("BIOS selectable resident boundary exceeds CODE")

    print("# DOS and BIOS residency census\n")
    print("## DOS high\n")
    print("| Range | Linked bytes | Paragraph allocation | Lifetime |")
    print("| --- | ---: | ---: | --- |")
    print(f"| Low entry/gateway prefix | {low_gate:,} | {rounded(low_gate):,} | retained low |")
    print(f"| HMA image after offset 0010h | {sysbuf - 0x10:,} | — | copied to `FFFF:0010` |")
    print(f"| LAST | {dos_last.size:,} | — | discarded initialization |")

    print("\n## BIOS\n")
    print(f"Linked `CODE` capacity: {bios_code.size:,} bytes. ")
    print(f"Discardable `SYSINITSEG`: {bios_init.size:,} bytes.\n")
    print("| Selectable boundary | Offset | Rounded bytes |")
    print("| --- | ---: | ---: |")
    for name, value in bios_boundaries:
        print(f"| {name} | `{value:04X}h` | {rounded(value):,} |")

    if errors:
        print("\n## Census errors\n")
        for error in errors:
            print(f"- {error}")
    return 1 if args.check and errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
