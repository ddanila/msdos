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
LABEL_RE = re.compile(
    r"^(\w+)\s+(?:\.\s*)+L\s+Near\s+([0-9A-F]+)h\s+_TEXT\s*$",
    re.IGNORECASE,
)


def bios_descriptor_span(path: Path) -> tuple[int, int]:
    """Identify firmware-facing data embedded in the move-backend inventory."""
    addresses = {}
    for line in path.read_text(encoding="latin-1").splitlines():
        match = LABEL_RE.match(line) or PROCEDURE_RE.match(line)
        if match:
            addresses[match[1]] = int(match[2], 16)
    start = addresses["move_gdt"]
    end = addresses["validate_handle"]
    if (end - start != 48
            or addresses["move_source_desc"] != start + 16
            or addresses["move_dest_desc"] != start + 24):
        raise ValueError("BIOS move descriptor layout is not the expected six-slot table")
    return start, end


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


BOOTSTRAP_PROCEDURES = (
    "bootstrap_copy_move", "set_move_descriptor", "xms_query_free", "xms_allocate",
    "xms_free", "xms_lock", "xms_unlock", "xms_handle_info", "xms_reallocate",
    "validate_handle", "find_gap", "largest_gap", "total_free", "gap_after_handle",
)
PERMANENT_PROCEDURES = (
    "private_bootstrap_layout",
    "xms_control", "xms_owner_handle", "xms_remote_owned", "xms_move",
    "xms_extended_handle_info", "xms_hma_request", "xms_hma_release",
    "xms_global_enable", "xms_global_disable", "xms_local_enable", "xms_local_disable",
    "xms_a20_query", "xms_umb_request", "xms_umb_release", "copy_move_blocks",
    *(f"xms_gate_{name}" for name in ("query", "allocate", "free", "lock", "unlock", "info", "reallocate")),
)


def check_bootstrap_layout(numbers, procedures, handle_count):
    """Linked boundary contract, not an assertion that the allocation is released."""
    start = numbers["HIMEM_PERMANENT_BYTES"]
    code = numbers["HIMEM_BOOTSTRAP_CODE_BYTES"]
    handles = numbers["HIMEM_HANDLES_OFFSET"]
    if (not 1 <= handle_count <= 128 or start <= 0 or start % 16 or code <= 0
            or start + code != handles or handles + 5 * handle_count > 65536):
        raise ValueError("invalid contiguous HIMEM bootstrap layout")
    for name in BOOTSTRAP_PROCEDURES:
        if not start <= procedures[name] < handles:
            raise ValueError(f"bootstrap procedure outside tail: {name}")
    for name in PERMANENT_PROCEDURES:
        if not 0 <= procedures[name] < start:
            raise ValueError(f"permanent entry in bootstrap tail: {name}")
    staging = ("private_bootstrap_stage", "xms_stage_forward")
    if any(name in procedures for name in staging):
        for name in staging:
            if not 0 <= procedures[name] < start:
                raise ValueError(f"staging entry in bootstrap tail: {name}")
    end = rounded(handles + 5 * handle_count)
    return dict(permanent_bytes=start, bootstrap_code_data_bytes=code,
                handles=handle_count, handle_bytes=5 * handle_count,
                linked_boot_end=end, retained_bootstrap_bytes=end-start,
                released_bytes=0)


def bootstrap_layout(path, handle_count):
    _, numbers = parse_symbols(path)
    procedures = {}
    for line in path.read_text(encoding="latin-1").splitlines():
        match = PROCEDURE_RE.match(line)
        if match:
            procedures[match[1]] = int(match[2], 16)
    return check_bootstrap_layout(numbers, procedures, handle_count)


def provider_ownership(path: Path, end: int) -> list[tuple[str, int, int, str]]:
    """Partition the original image by conversion boundary, not future size."""
    addresses = {}
    for line in path.read_text(encoding="latin-1").splitlines():
        match = PROCEDURE_RE.match(line) or LABEL_RE.match(line)
        if match:
            addresses[match[1]] = int(match[2], 16)
    boundaries = [
        ("Public/device/private-peer entries and bootstrap state", 0, "low interface redesign"),
        ("Dispatch, common returns, XMS 2/3 adapters", addresses["xms_control"], "split caller frame from backend"),
        ("HMA ownership", addresses["xms_hma_request"], "one authoritative bootstrap/high binding"),
        ("A20 policy and physical/BIOS backends", addresses["xms_global_enable"], "low transition binding"),
        ("EMB services including reallocating copy", addresses["xms_query_free"], "high data and copy binding"),
        ("Move descriptor validation", addresses["xms_move"], "real-pointer translation"),
        ("UMB services", addresses["xms_umb_request"], "shared peer/API data binding"),
        ("Move address resolution", addresses["resolve_move_address"], "high handle-data binding"),
        ("BIOS copy and descriptor construction", addresses["copy_move_blocks"], "replace on coordinated 386 path"),
        ("Physical-address helper and alignment", addresses["kb_to_physical"], "high service helper"),
        ("Firmware descriptor data", addresses["move_gdt"], "standalone BIOS backend only"),
        ("Handle and free-space helpers", addresses["validate_handle"], "high allocator-data binding"),
        ("end", end, ""),
    ]
    descriptor_start, descriptor_end = bios_descriptor_span(path)
    if addresses["move_gdt"] != descriptor_start or addresses["validate_handle"] != descriptor_end:
        raise ValueError("provider descriptor boundary mismatch")
    result = []
    for (owner, start, binding), (_, stop, _) in zip(boundaries, boundaries[1:]):
        if not 0 <= start < stop <= end:
            raise ValueError(f"unordered provider ownership range: {owner}")
        result.append((owner, start, stop, binding))
    return result


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
    descriptor_start, descriptor_end = bios_descriptor_span(args.listing)
    print(f"\nThe move-backend range contains {descriptor_end - descriptor_start} bytes")
    print(f"of BIOS-facing descriptor data at `{descriptor_start:04X}h..{descriptor_end:04X}h`;")
    print("this is nested in the inventory above, not additional code or savings.")
    print(f"The first split retains these descriptors and the {handles[0] - umb_count}-byte")
    print("UMB table low for the private register/unregister entry points.")

    print("\n## Coordinated-provider conversion boundaries\n")
    print("Existing linked bytes, not the size or low release of a new provider.\n")
    print("| Original owner | Range | Bytes | Required binding/change |")
    print("| --- | --- | ---: | --- |")
    for owner, start, stop, binding in provider_ownership(args.listing, umb_count):
        print(f"| {owner} | `{start:04X}h..{stop:04X}h` | {stop - start:,} | {binding} |")
    print("\nSelected handles and UMB records are the separate data owners above.")
    print("Reallocation calls the copy backend too; replacing only public Move")
    print("leaves the allocator dependent on BIOS. Low gates, protected copy code,")
    print("selectors and transition frames still require their own linked budget.")

    if errors:
        print("\n## Census errors\n")
        for error in errors:
            print(f"- {error}")
    return 1 if args.check and errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
