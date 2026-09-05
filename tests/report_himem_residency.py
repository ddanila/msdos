#!/usr/bin/env python3
"""Report HIMEM's fixed, option-sized, and discardable binary ranges."""

from __future__ import annotations

import argparse
from pathlib import Path
import re


SYMBOL_RE = re.compile(
    r"^(\w+)\s+(?:\.\s*)+(?:Byte(?:\[(\d+)\])?|Word)\s+([0-9A-F]+)h\s+_TEXT\s*$",
    re.IGNORECASE,
)
NUMBER_RE = re.compile(
    r"^(\w+)\s+(?:\.\s*)+Number\s+([0-9A-F]+)h\s*$", re.IGNORECASE
)
PROCEDURE_RE = re.compile(
    r"^(\w+)\s+(?:\.\s*)+P\s+(?:Near|Far)\s+([0-9A-F]+)\s+_TEXT\b",
    re.IGNORECASE,
)


def parse_symbols(path: Path) -> tuple[dict[str, tuple[int, int]], dict[str, int]]:
    symbols: dict[str, tuple[int, int]] = {}
    numbers: dict[str, int] = {}
    for raw in path.read_text(encoding="latin-1").splitlines():
        match = SYMBOL_RE.match(raw)
        if match:
            name, count, offset = match.groups()
            symbols[name] = (int(offset, 16), int(count or 1))
        match = NUMBER_RE.match(raw)
        if match:
            name, value = match.groups()
            numbers[name] = int(value, 16)
    return symbols, numbers


def fixed_ownership(path: Path, end: int) -> list[tuple[str, int, int]]:
    """Partition linked code/state by service, without asserting relocatability."""
    procedures = {}
    for line in path.read_text(encoding="latin-1").splitlines():
        match = PROCEDURE_RE.match(line)
        if match:
            procedures[match[1]] = int(match[2], 16)
    boundaries = [
        ("Device/vector entries, private peer and low state", 0),
        ("XMS dispatcher, common returns and version/extended entry points", procedures["xms_control"]),
        ("HMA ownership and A20 control", procedures["xms_hma_request"]),
        ("EMB allocation/lock/reallocation services", procedures["xms_query_free"]),
        ("XMS move validation and dispatch", procedures["xms_move"]),
        ("UMB allocator and coalescing", procedures["xms_umb_request"]),
        ("Move address resolution and BIOS-copy backend", procedures["resolve_move_address"]),
        ("Handle and free-space helpers", procedures["validate_handle"]),
        ("end", end),
    ]
    result = []
    for (owner, start), (_, stop) in zip(boundaries, boundaries[1:]):
        if not 0 <= start < stop <= end:
            raise ValueError(f"unordered HIMEM ownership range: {owner}")
        result.append((owner, start, stop))
    return result


def rounded(value: int) -> int:
    return (value + 15) & ~15


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("listing", type=Path, help="JWasm -Sa listing for HIMEM.ASM")
    parser.add_argument("binary", type=Path, help="HIMEM binary assembled with the listing")
    parser.add_argument("--handles", type=int, default=32)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    symbols, numbers = parse_symbols(args.listing)
    required = ("umb_count", "umb_blocks", "handles", "resident_end")
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError(f"missing listing symbols: {', '.join(missing)}")

    umb_count = symbols["umb_count"][0]
    umb_blocks = symbols["umb_blocks"]
    handles = symbols["handles"]
    resident_end = symbols["resident_end"][0]
    handle_size = numbers.get("HANDLE_SIZE", 0)
    max_handles = numbers.get("MAX_HANDLES", 0)
    selected_end = handles[0] + args.handles * handle_size
    errors: list[str] = []

    if not 1 <= args.handles <= max_handles:
        errors.append(f"handle count must be in 1..{max_handles}")
    if umb_blocks[0] != umb_count + 2:
        errors.append("UMB block table no longer follows its word count")
    if handles[0] != umb_blocks[0] + umb_blocks[1]:
        errors.append("handle table no longer follows the UMB table")
    if handle_size <= 0 or handles[1] != max_handles * handle_size:
        errors.append("handle array size disagrees with its constants")
    if handles[0] + handles[1] != resident_end:
        errors.append("handle table does not end at resident_end")
    if resident_end >= args.binary.stat().st_size:
        errors.append("resident_end does not leave a discardable initialization tail")

    print("# HIMEM residency census\n")
    print(f"Selected `/NUMHANDLES={args.handles}`; maximum is {max_handles}.\n")
    print("| Range | Offset | Bytes | Lifetime |")
    print("| --- | ---: | ---: | --- |")
    print(f"| Fixed resident code and state | `0000h..{umb_count:04X}h` | {umb_count:,} | resident |")
    print(f"| UMB count and records | `{umb_count:04X}h..{handles[0]:04X}h` | {handles[0] - umb_count:,} | resident |")
    print(f"| Selected handle records | `{handles[0]:04X}h..{selected_end:04X}h` | {args.handles * handle_size:,} | option-sized resident |")
    print(f"| Unselected handle capacity | `{selected_end:04X}h..{resident_end:04X}h` | {resident_end - selected_end:,} | discarded |")
    print(f"| Initialization tail | `{resident_end:04X}h..{args.binary.stat().st_size:04X}h` | {args.binary.stat().st_size - resident_end:,} | discarded |")
    print(f"| **Installed allocation** | — | **{rounded(selected_end):,}** | paragraph-rounded |")

    print("\n## Service ownership (not a relocation budget)\n")
    print("| Owner | Range | Bytes |")
    print("| --- | --- | ---: |")
    for owner, start, stop in fixed_ownership(args.listing, umb_count):
        print(f"| {owner} | `{start:04X}h..{stop:04X}h` | {stop - start:,} |")
    print("\nAll these services currently use one real-mode CS/DS image. Moving")
    print("a service requires explicit entry, state and return ownership; A20")
    print("recovery cannot depend on code which requires A20 already enabled.")
    print("The BIOS-copy backend and caller stack are separate transition gates.")

    if errors:
        print("\n## Census errors\n")
        for error in errors:
            print(f"- {error}")
    return 1 if args.check and errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
