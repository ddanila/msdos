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

    constants_segment = dos_segments["CONSTANTS"]
    constants_start = constants_segment.paragraph * 16 + constants_segment.offset
    constants_end = constants_start + constants_segment.size
    constants_ranges: list[tuple[str, int | str, int | str]] = [
        ("Reserved DOSGROUP/HMA origin", constants_start, "MSCT001S"),
        ("Nucleus identity, retry, and arena state", "MSCT001S", "SYSINITVAR"),
        ("SYSINIT pointers and resident device state", "SYSINITVAR", "HASHINITVAR"),
        ("Buffer and EMS initialization state", "HASHINITVAR", "JShare"),
        ("SHARE compatibility dispatch", "JShare", "MSCT001E"),
        ("Bootstrap system file table", "CONST001S", "CARPOS"),
        ("Console input and editing buffers", "CARPOS", "PFLAG"),
        ("Global flags and network name", "PFLAG", "CritPatch"),
        ("Critical-section patch table", "CritPatch", "SWAP_START"),
        ("Process, error, allocation, and calendar state", "SWAP_START", "DEVCALL"),
        ("Device request packet", "DEVCALL", "IOCall"),
        ("Disk I/O and status packet", "IOCall", "CreatePDB"),
        ("UMB allocator and lock state", "CreatePDB", "CONST001E"),
        ("Contribution alignment", "CONST001E", "DMES001S"),
        ("DOS message identity fields", "DMES001S", constants_end),
    ]
    print("\n### Retained CONSTANTS ownership\n")
    print("| Range | Bytes | Owner |")
    print("| ---: | ---: | --- |")
    constants_total = 0
    for owner, start_ref, end_ref in constants_ranges:
        start = require(dos_symbols, start_ref) if isinstance(start_ref, str) else start_ref
        end = require(dos_symbols, end_ref) if isinstance(end_ref, str) else end_ref
        if end < start:
            errors.append(f"DOS CONSTANTS range {start_ref}..{end_ref} is reversed")
        size = end - start
        constants_total += size
        print(f"| `{start:04X}h..{end:04X}h` | {size:,} | {owner} |")
    print(f"| **Total** | **{constants_total:,}** | `CONSTANTS` |")
    if constants_total != constants_segment.size:
        errors.append("DOS CONSTANTS ownership does not cover the complete segment")

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

    table_segment = dos_segments["TABLE"]
    table_start = table_segment.paragraph * 16 + table_segment.offset
    table_end = table_start + table_segment.size
    table_ranges: list[tuple[str, int | str, int | str]] = [
        ("Version and calendar constants", table_start, "I21_MAP_E_TAB"),
        ("INT 21 allowed-error map", "I21_MAP_E_TAB", "ERR_TABLE_21"),
        ("INT 21 extended-error metadata", "ERR_TABLE_21", "ERR_TABLE_24"),
        ("INT 24 critical-error metadata", "ERR_TABLE_24", "ErrMap24"),
        ("Device-error translation map", "ErrMap24", "MAXCALL"),
        ("INT 21 dispatch table", "MAXCALL", "FOO"),
        ("Internal install-service dispatch", "FOO", "InterChar"),
        ("Interim-console state and optional banner", "InterChar", "SysInitTable"),
        ("SYSINIT communication table", "SysInitTable", "FastOpenTable"),
        ("FASTOPEN and directory exchange state", "FastOpenTable", "User_SP_2F"),
        ("INT 2F and configuration temporaries", "User_SP_2F", "MSG_EXTERROR"),
        ("Extended-error and cache metadata", "MSG_EXTERROR", "SWAP_AREA_TABLE"),
        ("Swap and fake-version state", "SWAP_AREA_TABLE", "MSC001S"),
        ("Absolute-disk map and HMA driver trampoline", "MSC001S", "DMES002S"),
        ("Country, case-folding, and DOS messages", "DMES002S", "CREAT001S"),
        ("Create-mode lookup table", "CREAT001S", "DEV001S"),
        ("Device-character lookup table", "DEV001S", "FCB001S"),
        ("FCB character-class table", "FCB001S", "FCB001E"),
        ("EXEC launch pointers", "FCB001E", "SRVC001S"),
        ("Server-call dispatch table", "SRVC001S", table_end),
    ]
    print("\n### Retained TABLE ownership\n")
    print("| Range | Bytes | Owner |")
    print("| ---: | ---: | --- |")
    table_total = 0
    for owner, start_ref, end_ref in table_ranges:
        start = require(dos_symbols, start_ref) if isinstance(start_ref, str) else start_ref
        end = require(dos_symbols, end_ref) if isinstance(end_ref, str) else end_ref
        if end < start:
            errors.append(f"DOS TABLE range {start_ref}..{end_ref} is reversed")
        size = end - start
        table_total += size
        print(f"| `{start:04X}h..{end:04X}h` | {size:,} | {owner} |")
    print(f"| **Total** | **{table_total:,}** | `TABLE` |")
    if table_total != table_segment.size:
        errors.append("DOS TABLE ownership does not cover the complete segment")

    code_ranges = [
        ("HMA driver request entry", "hma_driver_requests", "hma_low_dpbs"),
        ("Low DPB pointer workspace", "hma_low_dpbs", "hma_driver_xms"),
        ("HMA driver/XMS and null-device tail", "hma_driver_xms", "DOS_LOW_GATE_END"),
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

    relocated_gate_end = require(dos_symbols, "DOS_RELOCATED_GATE_END")
    relocated_ranges = [
        ("Absolute-disk gateway", "AbsSetup", "SYS_RETURN"),
        ("System/FCB return and error gateway", "SYS_RETURN", "INT2F"),
        ("INT 2F gateway", "INT2F", "DOS_RELOCATED_GATE_END"),
    ]
    print("\n### Relocated DOS gateways\n")
    print("| Range | Bytes | Owner |")
    print("| ---: | ---: | --- |")
    relocated_total = 0
    for owner, start_name, end_name in relocated_ranges:
        start = require(dos_symbols, start_name)
        end = require(dos_symbols, end_name)
        if end < start:
            errors.append(f"relocated DOS gateway {start_name}..{end_name} is reversed")
        size = end - start
        relocated_total += size
        print(f"| `{start:04X}h..{end:04X}h` | {size:,} | {owner} |")
    print(f"| **Total** | **{relocated_total:,}** | copied to HMA; retained for DOS=LOW |")
    if require(dos_symbols, "AbsSetup") != low_gate:
        errors.append("relocated DOS gateway does not begin at the low boundary")
    if relocated_gate_end <= low_gate:
        errors.append("relocated DOS gateway does not follow the low boundary")

    dispatcher_start = require(dos_symbols, "BUF_EMS_MAP_USER")
    dispatcher_end = require(dos_symbols, "MAP_CASE")
    print("\n### Relocated system-call dispatcher\n")
    print("| Range | Bytes | Lifetime |")
    print("| ---: | ---: | --- |")
    print(
        f"| `{dispatcher_start:04X}h..{dispatcher_end:04X}h` | "
        f"{dispatcher_end - dispatcher_start:,} | copied to HMA; retained only for DOS=LOW |"
    )
    if dispatcher_start < low_gate or dispatcher_end - dispatcher_start != 783:
        errors.append("DOS system-call dispatcher is not wholly above the low boundary")

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
    if selected > 8160:
        errors.append("selected resident BIOS exceeds the 8,160-byte ceiling")
    print("\n### Fixed comparison selection\n")
    print("QEMU `pc` selects one hard disk, no 96-TPI extension, no legacy AT-ROM fix, a CMOS clock, and no K09 extension.\n")
    print("| Retained piece | Input boundary | Copied bytes | Output boundary |")
    print("| --- | ---: | ---: | ---: |")
    print(f"| One-hard-disk base (`ENDONEHARD`) | — | {require(bios_symbols, 'ENDONEHARD'):,} | `{selected_base:04X}h` |")
    print(f"| `Daycnt_to_day` | `{selected_base:04X}h` | {day_size:,} | `{after_day:04X}h` |")
    print(f"| `Bin_to_bcd` | `{after_day:04X}h` | {bcd_size:,} | `{selected:04X}h` |")
    print(f"| **Selected resident BIOS** | — | — | **{selected:,} bytes** |")

    selected_bios_ranges: list[tuple[str, int | str, int | str]] = [
        ("Loader entry", 0, "BIO001S"),
        ("Core BIOS data and device headers", "BIO001S", "BIO001E"),
        ("Strategy and request dispatch", "BIO001E", "CON$READ"),
        ("Console services", "CON$READ", "AUX$READ"),
        ("Auxiliary-device services", "AUX$READ", "PRN$WRIT"),
        ("Printer services", "PRN$WRIT", "HaveCMOSClock"),
        ("Clock services", "HaveCMOSClock", "Fat_12_ID"),
        ("Disk media constants", "Fat_12_ID", "MEDIA$CHK"),
        ("Media-change and BPB services", "MEDIA$CHK", "READ_SECTOR"),
        ("Sector and low-level disk I/O", "READ_SECTOR", "DISK"),
        ("Disk transfer and error paths", "DISK", "GENERIC$IOCTL"),
        ("Generic disk IOCTL and INT 2F services", "GENERIC$IOCTL", "DISK005S"),
        ("BIOS model and saved-vector state", "DISK005S", "DISK005E"),
        ("Disk initialization and reinitialization", "DISK005E", "CLK001S"),
        ("Clock swap state", "CLK001S", "ENDFLOPPY"),
        ("First hard-disk descriptor", "ENDFLOPPY", "ENDONEHARD"),
    ]
    print("\n### Selected resident BIOS ownership\n")
    print("| Source range | Bytes | Owner |")
    print("| ---: | ---: | --- |")
    selected_bios_total = 0
    for owner, start_ref, end_ref in selected_bios_ranges:
        start = require(bios_symbols, start_ref) if isinstance(start_ref, str) else start_ref
        end = require(bios_symbols, end_ref) if isinstance(end_ref, str) else end_ref
        if end < start:
            errors.append(f"BIOS resident range {start_ref}..{end_ref} is reversed")
        size = end - start
        selected_bios_total += size
        print(f"| `{start:04X}h..{end:04X}h` | {size:,} | {owner} |")
    print(f"| relocated `Daycnt_to_day` | {day_size:,} | CMOS day conversion |")
    print(f"| relocated `Bin_to_bcd` | {bcd_size:,} | CMOS BCD conversion |")
    selected_padding = selected - (selected_bios_total + day_size + bcd_size)
    print(f"| loader paragraph alignment | {selected_padding:,} | static and relocated-piece padding |")
    selected_bios_total += day_size + bcd_size + selected_padding
    print(f"| **Total** | **{selected_bios_total:,}** | selected resident BIOS |")
    if selected_bios_total != selected:
        errors.append("BIOS ownership does not cover the complete selected image")

    if errors:
        print("\n## Census errors\n")
        for error in errors:
            print(f"- {error}")
    return 1 if args.check and errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
