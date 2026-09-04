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
    parser.add_argument("--buffers", type=int, default=15)
    parser.add_argument("--sector-size", type=int, default=512)
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
    day_to_day = require(bios_symbols, "Daycnt_to_day")
    day_to_day_end = require(bios_symbols, "EndDaycntToDay")
    bin_to_bcd = require(bios_symbols, "Bin_to_bcd")
    bin_to_bcd_end = require(bios_symbols, "EndCMOSClockset")

    errors: list[str] = []
    if low_gate >= sysbuf:
        errors.append("DOS low gateway does not precede SYSBUF")
    if dos_last.paragraph * 16 != sysbuf:
        errors.append("DOS LAST segment no longer begins at SYSBUF")
    if any(left[1] >= right[1] for left, right in zip(bios_boundaries, bios_boundaries[1:])):
        errors.append("BIOS selectable resident boundaries are not ordered")
    if bios_boundaries[-1][1] > bios_code.size:
        errors.append("BIOS selectable resident boundary exceeds CODE")
    if not (day_to_day < day_to_day_end <= bin_to_bcd < bin_to_bcd_end):
        errors.append("BIOS CMOS helper ranges are not ordered")

    print("# DOS and BIOS residency census\n")
    print("## DOS high\n")
    print("| Range | Linked bytes | Paragraph allocation | Lifetime |")
    print("| --- | ---: | ---: | --- |")
    print(f"| Low entry/gateway prefix | {low_gate:,} | {rounded(low_gate):,} | retained low |")
    print(f"| HMA image after offset 0010h | {sysbuf - 0x10:,} | — | copied to `FFFF:0010` |")
    print(f"| LAST | {dos_last.size:,} | — | discarded initialization |")

    print("\n### Low-prefix composition\n")
    print("| Segment | Bytes below boundary | Role |")
    print("| --- | ---: | --- |")
    low_composition: list[tuple[str, int, str]] = []
    roles = {
        "START": "loader entry",
        "CONSTANTS": "resident constants",
        "DATA": "resident mutable data",
        "TABLE": "resident dispatch/data tables",
        "CODE": "low entry, driver, and interrupt gateway code",
    }
    for name in ("START", "CONSTANTS", "DATA", "TABLE", "CODE"):
        segment = dos_segments[name]
        start = segment.paragraph * 16 + segment.offset
        retained = max(0, min(start + segment.size, low_gate) - start)
        low_composition.append((name, retained, roles[name]))
        print(f"| {name} | {retained:,} | {roles[name]} |")
    composition_total = sum(size for _, size, _ in low_composition)
    composition_gap = low_gate - composition_total
    print(f"| Inter-segment alignment | {composition_gap:,} | linker padding |")
    print(f"| **Total** | **{composition_total + composition_gap:,}** | `DOS_LOW_GATE_END` |")
    if composition_total + composition_gap != low_gate:
        errors.append("DOS low-prefix composition does not reach DOS_LOW_GATE_END")

    # BUFFINFO is 20 bytes and BUFFER_HASH_ENTRY is 8 bytes in BUFFER.INC.
    # The fixed parity configuration uses one bucket for 15 buffers. SYSINIT
    # rejects a layout ending above FFFF:FFF0, preserving the final 16 bytes.
    buffer_header = 20
    hash_entry = 8
    hma_limit = 0xFFF0
    hma_buffer_base = sysbuf
    hma_buffer_bytes = args.buffers * (args.sector_size + buffer_header) + hash_entry
    hma_buffer_end = hma_buffer_base + hma_buffer_bytes
    hma_slack = hma_limit - hma_buffer_end
    if args.buffers < 1:
        errors.append("buffer count must be positive")
    if args.sector_size < 128 or args.sector_size > 0xFFFF - buffer_header:
        errors.append("sector size is outside the supported census range")
    if hma_slack < 0:
        errors.append("selected buffers do not fit below the HMA safety tail")

    print("\n### Fixed HMA ownership\n")
    print(f"Selected `{args.buffers}` buffers with {args.sector_size}-byte sectors.\n")
    print("| Range | Offset | Bytes | Owner/lifetime |")
    print("| --- | ---: | ---: | --- |")
    print(f"| DOS high image | `0010h..{hma_buffer_base:04X}h` | {hma_buffer_base - 0x10:,} | DOS; entire high-mode lifetime |")
    print(f"| Hash plus buffer slots | `{hma_buffer_base:04X}h..{hma_buffer_end:04X}h` | {hma_buffer_bytes:,} | DOS cache; entire high-mode lifetime |")
    print(f"| Available DOS-owned high storage | `{hma_buffer_end:04X}h..{hma_limit:04X}h` | {max(0, hma_slack):,} | unassigned, but not available through XMS |")
    print(f"| HMA safety tail | `{hma_limit:04X}h..10000h` | {0x10000 - hma_limit:,} | deliberately unused |")

    data_ranges = [
        ("Core file/disk workspace", "MSDAT001S", "RENAMEDMA"),
        ("Rename/search workspace", "RENAMEDMA", "AuxStack"),
        ("Auxiliary interrupt stack", "AuxStack", "DskStack"),
        ("Disk interrupt stack", "DskStack", "IOStack"),
        ("Resident I/O and fast-seek state", "IOStack", "SWAP_END"),
        ("Required swap-rounding byte", "SWAP_END", "MSDAT001E"),
    ]
    print("\n### Retained DATA ownership\n")
    print("| Range | Bytes | Owner |")
    print("| ---: | ---: | --- |")
    data_total = 0
    for owner, start_name, end_name in data_ranges:
        start = require(dos_symbols, start_name)
        end = require(dos_symbols, end_name)
        if end < start:
            errors.append(f"DOS DATA range {start_name}..{end_name} is reversed")
        size = end - start
        data_total += size
        print(f"| `{start:04X}h..{end:04X}h` | {size:,} | {owner} |")
    print(f"| **Total** | **{data_total:,}** | `DATA` |")
    if data_total != dos_segments["DATA"].size:
        errors.append("DOS DATA ownership does not cover the complete segment")

    code_ranges = [
        ("EMS user-map buffer", "BUF_EMS_MAP_USER", "DOS_CODE_START"),
        ("Core system-call dispatcher", "DOS_CODE_START", "hma_driver_requests"),
        ("HMA driver request entry", "hma_driver_requests", "hma_low_dpbs"),
        ("Low DPB pointer workspace", "hma_low_dpbs", "hma_driver_xms"),
        ("HMA driver/XMS tail", "hma_driver_xms", "AbsSetup"),
        ("Absolute-disk gateway", "AbsSetup", "SYS_RETURN"),
        ("System/FCB return and error gateway", "SYS_RETURN", "INT2F"),
        ("INT 2F gateway", "INT2F", "DOS_LOW_GATE_END"),
    ]
    print("\n### Retained CODE ownership\n")
    print("| Range | Bytes | Owner |")
    print("| ---: | ---: | --- |")
    code_total = 0
    for owner, start_name, end_name in code_ranges:
        start = require(dos_symbols, start_name)
        end = require(dos_symbols, end_name)
        if end < start:
            errors.append(f"DOS CODE range {start_name}..{end_name} is reversed")
        size = end - start
        code_total += size
        print(f"| `{start:04X}h..{end:04X}h` | {size:,} | {owner} |")
    print(f"| **Total** | **{code_total:,}** | retained `CODE` |")
    code_segment = dos_segments["CODE"]
    retained_code = low_gate - (code_segment.paragraph * 16 + code_segment.offset)
    if code_total != retained_code:
        errors.append("DOS CODE ownership does not cover the complete retained prefix")

    print("\n## BIOS\n")
    print(f"Linked `CODE` capacity: {bios_code.size:,} bytes. ")
    print(f"Discardable `SYSINITSEG`: {bios_init.size:,} bytes.\n")
    print("| Selectable boundary | Offset | Rounded bytes |")
    print("| --- | ---: | ---: |")
    for name, value in bios_boundaries:
        print(f"| {name} | `{value:04X}h` | {rounded(value):,} |")

    # The fixed parity image presents one hard disk and a CMOS clock. MSINIT
    # starts at ENDONEHARD, then independently copies and paragraph-aligns the
    # two clock helpers. The paired MCB capture provides an external check: this
    # computed boundary is the BIOS part of the grouped pre-MCB payload.
    selected_base = rounded(require(bios_symbols, "ENDONEHARD"))
    selected = selected_base
    day_size = day_to_day_end - day_to_day
    bcd_size = bin_to_bcd_end - bin_to_bcd
    after_day = selected + day_size
    selected = rounded(after_day + bcd_size)
    if selected > 8496:
        errors.append("selected resident BIOS exceeds the 8,496-byte ceiling")
    print("\n### Fixed comparison selection\n")
    print("QEMU `pc` selects one hard disk, no 96-TPI extension, no legacy AT-ROM fix, a CMOS clock, and no K09 extension.\n")
    print("| Retained piece | Input boundary | Copied bytes | Output boundary |")
    print("| --- | ---: | ---: | ---: |")
    print(f"| One-hard-disk base (`ENDONEHARD`) | — | {require(bios_symbols, 'ENDONEHARD'):,} | `{selected_base:04X}h` |")
    print(f"| `Daycnt_to_day` | `{selected_base:04X}h` | {day_size:,} | `{after_day:04X}h` |")
    print(f"| `Bin_to_bcd` | `{after_day:04X}h` | {bcd_size:,} | `{selected:04X}h` |")
    print(f"| **Selected resident BIOS** | — | — | **{selected:,} bytes** |")

    if errors:
        print("\n## Census errors\n")
        for error in errors:
            print(f"- {error}")
    return 1 if args.check and errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
