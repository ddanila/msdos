#!/usr/bin/env python3
"""Attribute activation-time low-DOS segment matches; never infer fixups."""
import argparse
import hashlib
import struct
from pathlib import Path

from report_dos_bios_residency import parse_map


def records(data):
    result = {}
    cursor = 0
    for expected in "HLBDIC":
        if cursor + 7 > len(data):
            raise ValueError("truncated census header")
        tag = chr(data[cursor])
        segment, offset, length = struct.unpack_from("<HHH", data, cursor + 1)
        cursor += 7
        if tag != expected or not length or cursor + length > len(data):
            raise ValueError("invalid census region/order/length")
        result[tag] = (segment, offset, data[cursor:cursor + length])
        cursor += length
    if cursor != len(data):
        raise ValueError("unexpected bytes after census")
    return result


def matches(offset, data, segment):
    needle = struct.pack("<H", segment)
    # Far pointers need not be word aligned. Adjacent words can also be plain
    # data or instructions; this deliberately broad scan is not a patch list.
    for index in range(len(data) - 1):
        if data[index:index + 2] == needle:
            target = struct.unpack_from("<H", data, index - 2)[0] if index >= 2 else None
            yield offset + index, target


def owner(symbols, offset):
    eligible = [(value, name) for name, value in symbols.items() if value <= offset]
    if not eligible:
        return "unattributed"
    value, name = max(eligible)
    return f"{name}+{offset - value:04X}h"


def report(scan, dos_map, bios_map, output):
    data = scan.read_bytes()
    regions = records(data)
    _, dos_symbols = parse_map(dos_map)
    bios_segments, bios_symbols = parse_map(bios_map)
    init_segment = bios_segments["SYSINITSEG"]
    init_base = init_segment.paragraph * 16 + init_segment.offset
    init_symbols = {name: value - init_base for name, value in bios_symbols.items()
                    if init_base <= value < init_base + init_segment.size}
    low_segment, low_offset, low_data = regions["L"]
    high_segment, high_offset, high_data = regions["H"]
    if high_segment != 0xffff or high_offset != 0x10:
        raise ValueError("unexpected HMA ownership")
    if len(high_data) != dos_symbols["SYSBUF"] - high_offset:
        raise ValueError("recorded HMA image does not match DOS map")
    low_owner_offset = dos_symbols["hma_low_segment"] - high_offset
    if struct.unpack_from("<H", high_data, low_owner_offset)[0] != low_segment:
        raise ValueError("HMA low owner does not match recorded low segment")
    if low_offset != 0 or len(low_data) != dos_symbols["DOS_LOW_GATE_END"]:
        raise ValueError("recorded low prefix does not match DOS map")
    lines = ["# BIOS activation: DOS low-owner census", "",
             "Read-only snapshot before rebasing. Matches are numeric candidates, not",
             "proved pointers or permission to rewrite words. Symbol names identify the",
             "nearest preceding export; inspect its declared structure and consumers.", "",
             f"Low DOS segment: `{low_segment:04X}h`.", "",
             f"Snapshot SHA-256: `{hashlib.sha256(data).hexdigest()}`.", "",
             f"DOS map SHA-256: `{hashlib.sha256(dos_map.read_bytes()).hexdigest()}`.", "",
             f"BIOS map SHA-256: `{hashlib.sha256(bios_map.read_bytes()).hexdigest()}`.", "",
             "| Region | Segment | Offset | Bytes |", "| --- | ---: | ---: | ---: |"]
    names = dict(H="HMA DOS", L="Low DOS prefix", B="Permanent BIOS",
                 D="Boot allocation", I="SYSINIT (includes live stack)", C="Initial CDS table")
    for tag, (segment, offset, payload) in regions.items():
        lines.append(f"| {names[tag]} | {segment:04X}h | {offset:04X}h | {len(payload):,} |")
    lines += ["", "| Region | Matching word | Previous word | Nearest export |",
              "| --- | ---: | ---: | --- |"]
    for tag, (_, offset, payload) in regions.items():
        symbols = (dos_symbols if tag in "HL" else bios_symbols if tag == "B"
                   else init_symbols if tag == "I" else {})
        for location, target in matches(offset, payload, low_segment):
            preceding = "—" if target is None else f"{target:04X}h"
            lines.append(f"| {names[tag]} | {location:04X}h | {preceding} | {owner(symbols, location)} |")
    lines += ["", "This cannot find normalized segment aliases, encoded/computed addresses,",
              "or external references outside the captured regions. Source ownership,",
              "device/DPB/CDS/SFT chain audits, and destructive stale-copy tests remain",
              "required before approving a rebase. No conventional memory was reclaimed."]
    output.write_text("\n".join(lines) + "\n")
    print(f"Recorded relocation candidates: {output}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("scan", "dos_map", "bios_map", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    report(args.scan, args.dos_map, args.bios_map, args.output)
