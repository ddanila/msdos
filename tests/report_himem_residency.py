#!/usr/bin/env python3
"""Report HIMEM's fixed, option-sized, and discardable binary ranges."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re


SYMBOL_RE = re.compile(
    r"^(\w+)\s+(?:\.\s*)+(?:Byte(?:\[(\d+)\])?|D?Word(?:\[\d+\])?)\s+([0-9A-F]+)h\s+_TEXT\s*$",
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
    moved_move = "bootstrap_move" in procedures
    move_tail = ("bootstrap_move", "resolve_move_address", "copy_move_blocks", "kb_to_physical") if moved_move else ()
    import_tail = ("bootstrap_remote_owned",) if "bootstrap_remote_owned" in procedures else ()
    if "bootstrap_umb_import" in procedures:
        import_tail += ("bootstrap_umb_import", "umb_remote_send")
        if not 0 <= procedures["umb_remote"] < start:
            raise ValueError("UMB import lifetime guard is not permanent")
    umb_tail = ("bootstrap_umb_service", "xms_umb_request", "xms_umb_release") if "bootstrap_umb_service" in procedures else ()
    for name in (*BOOTSTRAP_PROCEDURES, *move_tail, *import_tail, *umb_tail):
        if not start <= procedures[name] < handles:
            raise ValueError(f"bootstrap procedure outside tail: {name}")
    for name in PERMANENT_PROCEDURES:
        if "xms_bootstrap_dispatch" in procedures and name.startswith("xms_gate_"):
            if name in procedures:
                raise ValueError("superseded per-service handle wrapper still exists")
            continue
        if moved_move and name in ("xms_owner_handle", "copy_move_blocks"):
            continue
        if umb_tail and name in umb_tail:
            continue
        if not 0 <= procedures[name] < start:
            raise ValueError(f"permanent entry in bootstrap tail: {name}")
    staging = ("private_bootstrap_stage", "xms_stage_forward")
    if "xms_bootstrap_dispatch" in procedures and not 0 <= procedures["xms_bootstrap_dispatch"] < start:
        raise ValueError("bootstrap dispatch guard is not permanent")
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
    symbols, numbers = parse_symbols(path)
    procedures = {}
    for line in path.read_text(encoding="latin-1").splitlines():
        match = PROCEDURE_RE.match(line)
        if match:
            procedures[match[1]] = int(match[2], 16)
    result = check_bootstrap_layout(numbers, procedures, handle_count)
    if "xms_bootstrap_dispatch" in procedures:
        if not (result["permanent_bytes"] <= symbols["bootstrap_handle_table"][0]
                and symbols["bootstrap_handle_table"][0] + 16 <= numbers["HIMEM_HANDLES_OFFSET"]):
            raise ValueError("local handle dispatch table is not in the bootstrap tail")
    if "bootstrap_umb_service" in procedures:
        if not (result["permanent_bytes"] <= symbols["umb_count"][0]
                and symbols["umb_blocks"][0] == symbols["umb_count"][0] + 2
                and symbols["umb_blocks"][0] + 128 <= numbers["HIMEM_HANDLES_OFFSET"]):
            raise ValueError("canonical UMB records are not in the bootstrap tail")
    return result


def paired_front_ownership(path, handle_count):
    """Inventory the actual paired front, not the original monolithic order."""
    symbols, _ = parse_symbols(path)
    addresses = {name: value[0] for name, value in symbols.items()}
    for line in path.read_text(encoding="latin-1").splitlines():
        match = PROCEDURE_RE.match(line) or LABEL_RE.match(line)
        if match:
            addresses[match[1]] = int(match[2], 16)
    layout = bootstrap_layout(path, handle_count)
    # These contracts classify present bytes; they do not predict gate sizes.
    boundaries = [
        ("Header and shared state", 0, "split escaped entries, canonical policy and transfer scratch"),
        ("Device INIT interface", addresses["strategy"], "stable header; initialization body has boot-only lifetime"),
        ("Multiplex and private peer entries", addresses["multiplex_handler"], "keep discovery and A20 recovery callable without high dispatch"),
        ("Private UMB registration", addresses["private_register"], "transfer registration and public allocation state as one owner"),
        ("INT 15 compatibility entry", addresses["int15_handler"], "retain real-mode chain and reported pool contract"),
        ("XMS dispatch and adapters", addresses["xms_control"], "preserve cached entry, caller frame and XMS 2/3 outputs"),
        ("HMA ownership", addresses["xms_hma_request"], "one live reservation bit; HMA is not a second allocator pool"),
        ("A20 policy and hardware", addresses["xms_global_enable"], "keep transition recovery independent of enabled A20/high services"),
        ("Bootstrap layout query", addresses["private_bootstrap_layout"], "boot negotiation; retain a defined response after retirement"),
    ]
    if "private_bootstrap_stage" in addresses:
        boundaries += [
            ("Bootstrap staging transaction", addresses["private_bootstrap_stage"], "boot-only implementation behind stable rejection after commit"),
            ("Bootstrap forwarding", addresses["xms_stage_forward"], "retire only after all live calls and cancellation end"),
        ]
    boundaries += [
        ("High allocator transport", addresses["xms_remote_owned"], "separate one-time import from permanent high dispatch"),
        ("Handle translation and gates", addresses.get("xms_bootstrap_dispatch", addresses.get("xms_owner_handle", addresses.get("xms_gate_query"))), "high authority with no low handle mirror"),
        ("Public Move validation", addresses["xms_move"], "bind real caller pointers and reject before writes"),
        ("UMB allocation and coalescing", addresses["xms_umb_request"], "move with registered table and peer operations, not independently"),
        ("Move address translation", addresses["resolve_move_address"], "share high handle lookup and physical address validation"),
        ("Protected copy entry", addresses["copy_move_blocks"], "preserve OFF/AUTO transition and unavailable-backend failure"),
        ("Physical address helper", addresses["kb_to_physical"], "service helper, not an independently budgeted relocation"),
        ("UMB records", addresses["umb_count"], "one authoritative register/allocate/unregister table"),
        ("Front alignment", addresses.get("himem_front_end", addresses["umb_blocks"] + symbols["umb_blocks"][1]), "charge final packing, not a payload owner"),
        ("end", layout["permanent_bytes"], ""),
    ]
    if "umb_remote_state" in addresses:
        index = next(i for i, row in enumerate(boundaries) if row[0] == "UMB records")
        boundaries.insert(index, ("UMB handoff transport and publication state",
                                   addresses["umb_remote_state"],
                                   "public/peer high owner; retain bootstrap fallback until packed release"))
        name, start, _ = boundaries[index + 1]
        boundaries[index + 1] = (name, start,
                                "bootstrap owner before commit; transient peer input afterward, not a live mirror")
    if "xms_public_move_front" in addresses:
        index = next(i for i, row in enumerate(boundaries) if row[0] == "UMB records")
        boundaries.insert(index, ("Public Move descriptor adapter", addresses["xms_public_move_front"],
                                  "bounded caller snapshot and result binding; validation uses the high owner"))
    if "xms_bound_entry" in addresses:
        index = next(i for i, row in enumerate(boundaries) if row[0] == "UMB records")
        boundaries.insert(index, ("Common provider binding", addresses["xms_bound_entry"],
                                  "one resident guarded entry per boot; no fallback after binding"))
    if "common_busy" in addresses:
        index = next(i for i, row in enumerate(boundaries) if row[0] == "UMB records")
        boundaries.insert(index, ("Common caller frame", addresses["common_busy"],
                                  "shared input snapshot, serialization and sequenced results"))
        name, start, _ = boundaries[index + 1]
        boundaries[index + 1] = (name, start, "bootstrap-only owner; common peer input uses the shared frame")
    for symbol, name in (("umb_boot_import_tries", "Bootstrap owner completion"),
                         ("umb_local_call", "Bootstrap UMB gate")):
        if symbol in addresses:
            index = next(i for i, row in enumerate(boundaries) if row[0] == "UMB records")
            boundaries.insert(index, (name, addresses[symbol], "retain lifetime checks; bootstrap body/state are separately owned"))
    already_retired = set()
    if "bootstrap_umb_service" in addresses:
        already_retired |= {"Private UMB registration", "UMB allocation and coalescing", "UMB records"}
        boundaries = [("Private UMB gates", start, "public wrapper; local bodies and records belong to bootstrap")
                      if name == "Private UMB registration" else (name, start, contract)
                      for name, start, contract in boundaries
                      if name not in {"UMB allocation and coalescing", "UMB records"}]
    if "bootstrap_remote_owned" in addresses:
        boundaries = [("High allocator gate", start, "permanent freeze/publication guard; import body is bootstrap-only")
                      if name == "High allocator transport" else (name, start, contract)
                      for name, start, contract in boundaries]
    if "xms_bootstrap_dispatch" in addresses:
        boundaries = [("Shared bootstrap handle dispatch", start,
                       "one lifetime gate; local target table is bootstrap-only")
                      if name == "Handle translation and gates" else (name, start, contract)
                      for name, start, contract in boundaries]
    if "bootstrap_umb_import" in addresses:
        boundaries = [("UMB import gate and publication state", start,
                       "import body is bootstrap-only; keep outcome state and permanent rejection")
                      if name == "UMB handoff transport and publication state" else (name, start, contract)
                      for name, start, contract in boundaries]
    if "bootstrap_move" in addresses:
        already_retired |= {"Public Move validation", "Move address translation",
                           "Protected copy entry", "Physical address helper"}
        boundaries = [("Public Move gate", start, "bootstrap/high lifetime selection; never enter retired storage")
                      if name == "Public Move validation" else (name, start, contract)
                      for name, start, contract in boundaries
                      if name not in already_retired - {"Public Move validation"}]
    rows = []
    for (owner, start, contract), (_, end, _) in zip(boundaries, boundaries[1:]):
        if not 0 <= start <= end <= layout["permanent_bytes"]:
            raise ValueError(f"unordered paired front: {owner}")
        rows.append(dict(owner=owner, start=start, end=end, bytes=end-start, contract=contract))
    if sum(row["bytes"] for row in rows) != layout["permanent_bytes"]:
        raise ValueError("paired front has unaccounted bytes")
    return dict(layout=layout, front=rows, transplant_counterfactual=transplant_counterfactual(rows, already_retired=already_retired),
                projected_low_bytes=None,
                projected_release_bytes=None)


def transplant_counterfactual(rows, *, already_retired=frozenset()):
    """Price one hypothetical deletion, not relocatability or a final layout.

    Delete complete boot/UMB/Move groups while retaining the present transports
    and everything else. This deliberately deletes required peer wrappers and
    scratch too, and charges no replacement gates. It can reject an attractive
    but insufficient design sequence; it cannot predict its achievable saving.
    """
    removed_names = {
        "Bootstrap layout query", "Bootstrap staging transaction", "Bootstrap forwarding",
        "Private UMB registration", "UMB allocation and coalescing", "UMB records",
        "Public Move validation", "Move address translation", "Protected copy entry",
        "Physical address helper",
    }
    optional = {"Bootstrap staging transaction", "Bootstrap forwarding"}
    by_name = {row["owner"]: row for row in rows}
    if (not set(already_retired) <= removed_names or set(already_retired) & by_name.keys()
            or len(by_name) != len(rows) or (removed_names - optional - set(already_retired)) - by_name.keys()):
        raise ValueError("incomplete or duplicate transplant accounting groups")
    removed = [row for row in rows if row["owner"] in removed_names]
    retained = [row for row in rows if row["owner"] not in removed_names]
    return dict(removed_groups=[row["owner"] for row in removed],
                already_retired_groups=sorted(already_retired),
                removed_linked_bytes=sum(row["bytes"] for row in removed),
                retained_linked_bytes=sum(row["bytes"] for row in retained),
                replacement_gate_bytes=None, final_low_bytes=None,
                note="Hypothetical deletion with current transports and alignment retained; "
                     "excludes EMM, high costs and replacement interfaces. Not reclaimable bytes.")


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
    parser.add_argument("--paired", action="store_true", help="inventory the authoritative paired front")
    parser.add_argument("--json", action="store_true", help="machine-readable paired inventory")
    args = parser.parse_args()
    if args.json and not args.paired:
        parser.error("--json requires --paired")
    if args.paired:
        report = paired_front_ownership(args.listing, args.handles)
        if report["layout"]["linked_boot_end"] >= args.binary.stat().st_size:
            raise ValueError("paired bootstrap extent exceeds the load image")
        report["listing_sha256"] = hashlib.sha256(args.listing.read_bytes()).hexdigest()
        report["binary_sha256"] = hashlib.sha256(args.binary.read_bytes()).hexdigest()
        report["identity_note"] = "Input hashes identify supplied files; not proof they were assembled together."
        if args.json:
            print(json.dumps(report, indent=2))
        else:
            print("# Paired HIMEM front ownership\n")
            print("Present linked bytes and required contracts, not a final layout or savings forecast.\n")
            print("| Owner | Range | Bytes | Required contract |")
            print("| --- | --- | ---: | --- |")
            for row in report["front"]:
                print(f'| {row["owner"]} | `{row["start"]:04X}..{row["end"]:04X}` | {row["bytes"]} | {row["contract"]} |')
            print(f'\nPermanent front: {report["layout"]["permanent_bytes"]} bytes. '
                  'Bootstrap release must be measured separately; complete provider also includes EMM386.')
            scenario = report["transplant_counterfactual"]
            print(f'\nDeleting all inventoried bootstrap, UMB peer/services/records and Move groups '
                  f'would remove {scenario["removed_linked_bytes"]} linked bytes and leave '
                  f'{scenario["retained_linked_bytes"]} with the present transports. '
                  'Replacement interfaces are unpriced; this is not a release or final-size forecast.')
        return 0

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
