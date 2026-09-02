#!/usr/bin/env python3
"""Classify linker-visible EMM386 ranges and symbols by installed lifetime."""

from __future__ import annotations

import argparse
from collections import Counter
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
MODULE_RE = re.compile(r"^Module:\s+(.*)$")


@dataclass(frozen=True)
class Segment:
    name: str
    paragraph: int
    offset: int
    size: int


@dataclass(frozen=True)
class Symbol:
    paragraph: int
    offset: int
    name: str
    module: str


def parse_map(path: Path) -> tuple[list[Segment], list[Symbol]]:
    segments: list[Segment] = []
    symbols: list[Symbol] = []
    section = ""
    module = ""
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
        if "|   Linker Statistics   |" in raw:
            section = ""
            continue
        if section == "segments":
            match = SEGMENT_RE.match(raw)
            if match:
                name, paragraph, offset, size = match.groups()
                segments.append(
                    Segment(name, int(paragraph, 16), int(offset, 16), int(size, 16))
                )
        elif section == "symbols":
            module_match = MODULE_RE.match(raw)
            if module_match:
                module = module_match.group(1)
                continue
            match = SYMBOL_RE.match(raw)
            if match:
                paragraph, offset, name = match.groups()
                symbols.append(Symbol(int(paragraph, 16), int(offset, 16), name, module))
    if not segments or not symbols:
        raise ValueError(f"could not parse segments and symbols from {path}")
    return segments, symbols


def classify_segment(name: str) -> str | None:
    return {
        "R_CODE": "retained real-mode gateway",
        "GDT": "retained descriptor state",
        "LDT": "empty",
        "_DATA": "retained mutable runtime data",
        "CONST": "retained runtime data",
        "CONST2": "retained runtime data",
        "_BSS": "retained mutable runtime data",
        "STACK": "initialization stack template",
        "_TEXT": "split retained/relocated code",
        "VDATA": "dynamic data compacted into low _TEXT suffix",
        "PAGESEG": "relocated to locked XMS",
        "IDT": "relocated to locked XMS",
        "TSS": "relocated to locked XMS",
        "LAST": "discarded initialization state",
    }.get(name)


def classify_symbol(
    symbol: Symbol,
    segment_categories: dict[int, str],
    text_segment: int,
    split: int,
    r_code_size: int,
) -> str | None:
    if symbol.paragraph == text_segment:
        if symbol.offset < split:
            return "retained/dual-mode _TEXT prefix"
        return "protected-only _TEXT copy in locked XMS"
    if symbol.paragraph == 0:
        if symbol.offset < r_code_size:
            return "retained real-mode gateway"
        return "absolute/link-time constant"
    return segment_categories.get(symbol.paragraph)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("map", type=Path, help="Open Watcom EMM386 map file")
    parser.add_argument(
        "--check", action="store_true", help="fail if a segment or symbol is unclassified"
    )
    args = parser.parse_args()
    segments, symbols = parse_map(args.map)

    by_name = {segment.name: segment for segment in segments}
    text = by_name["_TEXT"]
    r_code = by_name["R_CODE"]
    segment_categories = {
        by_name["GDT"].paragraph: "retained descriptor state",
        by_name["_DATA"].paragraph: "retained mutable runtime data",
        by_name["STACK"].paragraph: "initialization stack template",
        by_name["VDATA"].paragraph: "dynamic data compacted into low _TEXT suffix",
        by_name["PAGESEG"].paragraph: "relocated to locked XMS",
        by_name["IDT"].paragraph: "relocated to locked XMS",
        by_name["TSS"].paragraph: "relocated to locked XMS",
        by_name["LAST"].paragraph: "discarded initialization state",
    }
    split_symbols = [symbol for symbol in symbols if symbol.name == "IOTrap_Tab"]
    if len(split_symbols) != 1:
        raise ValueError("expected exactly one IOTrap_Tab split symbol")
    split = split_symbols[0].offset

    print("# EMM386 residency census\n")
    print(f"Map: `{args.map}`\n")
    print("| Segment | Link address | Linked bytes | Lifetime |")
    print("| --- | ---: | ---: | --- |")
    unknown_segments: list[str] = []
    for segment in segments:
        category = classify_segment(segment.name)
        if category is None:
            category = "UNCLASSIFIED"
            unknown_segments.append(segment.name)
        print(
            f"| {segment.name} | `{segment.paragraph:04X}:{segment.offset:04X}` "
            f"| {segment.size:,} | {category} |"
        )

    counts: Counter[str] = Counter()
    unknown_symbols: list[Symbol] = []
    for symbol in symbols:
        category = classify_symbol(
            symbol, segment_categories, text.paragraph, split, r_code.size
        )
        if category is None:
            unknown_symbols.append(symbol)
        else:
            counts[category] += 1

    print("\n## Linker-visible symbols\n")
    print(
        f"The `_TEXT` ownership boundary is `IOTrap_Tab` at "
        f"`{text.paragraph:04X}:{split:04X}`: {split:,} low bytes and "
        f"{text.size - split:,} protected-only bytes.\n"
    )
    print("| Lifetime | Symbols |")
    print("| --- | ---: |")
    for category, count in sorted(counts.items()):
        print(f"| {category} | {count} |")
    print(f"| UNCLASSIFIED | {len(unknown_symbols)} |")

    if unknown_segments or unknown_symbols:
        print("\n## Unclassified entries\n")
        for name in unknown_segments:
            print(f"- segment `{name}`")
        for symbol in unknown_symbols:
            print(
                f"- `{symbol.paragraph:04X}:{symbol.offset:04X}` `{symbol.name}` "
                f"from `{symbol.module}`"
            )
    if args.check and (unknown_segments or unknown_symbols):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
