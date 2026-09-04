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


@dataclass(frozen=True)
class Range:
    start: int
    end: int
    owner: str

    @property
    def size(self) -> int:
        return self.end - self.start


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
        "STACK": "discarded initialization stack",
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
        return "non-low _TEXT copy in locked XMS"
    if symbol.paragraph == 0:
        if symbol.offset < r_code_size:
            return "retained real-mode gateway"
        return "absolute/link-time constant"
    return segment_categories.get(symbol.paragraph)


def linear(paragraph: int, offset: int) -> int:
    return paragraph * 16 + offset


def symbol_offset(symbols: list[Symbol], name: str, paragraph: int) -> int:
    matches = [
        symbol.offset
        for symbol in symbols
        if symbol.name == name and symbol.paragraph == paragraph
    ]
    if len(matches) != 1:
        raise ValueError(f"expected exactly one {name} symbol in segment {paragraph:04X}")
    return matches[0]


def print_ranges(title: str, ranges: list[Range]) -> None:
    print(f"\n## {title}\n")
    print("| Range | Bytes | Owner |")
    print("| ---: | ---: | --- |")
    for item in ranges:
        print(f"| `{item.start:04X}h..{item.end:04X}h` | {item.size:,} | {item.owner} |")
    print(f"| **Total** | **{sum(item.size for item in ranges):,}** | — |")


def display_module(module: str) -> str:
    match = re.search(r"emmlib\.lib\((.*)\)$", module, re.IGNORECASE)
    if match:
        return f"emmlib:{Path(match.group(1)).name}"
    return module


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("map", type=Path, help="Open Watcom EMM386 map file")
    parser.add_argument("--handles", type=int, default=64, help="selected H= capacity")
    parser.add_argument(
        "--alternate-registers", type=int, default=7, help="selected A= capacity"
    )
    parser.add_argument(
        "--ems-pages", type=int, default=64, help="selected 16 KiB backing pages"
    )
    parser.add_argument(
        "--physical-pages", type=int, default=4, help="selected mappable windows"
    )
    parser.add_argument(
        "--check", action="store_true", help="fail if a segment or symbol is unclassified"
    )
    args = parser.parse_args()
    if not 2 <= args.handles <= 255:
        parser.error("--handles must be in 2..255")
    if not 0 <= args.alternate_registers <= 255:
        parser.error("--alternate-registers must be in 0..255")
    if not 0 <= args.ems_pages <= 4095:
        parser.error("--ems-pages must be in 0..4095")
    if not 0 <= args.physical_pages <= 52:
        parser.error("--physical-pages must be in 0..52")
    segments, symbols = parse_map(args.map)
    if args.check and any(symbol.name == "_page_frame_base" for symbol in symbols):
        raise ValueError("redundant physical-window PTE-offset table is resident")
    if args.check and any(
        symbol.name in {"EMM_MPindex", "_EMM_MPindex"} for symbol in symbols
    ):
        raise ValueError("redundant segment-to-window index is resident")
    if args.check and any(
        symbol.name in {"EMM_Protected_Functions", "EFunTab"} for symbol in symbols
    ):
        raise ValueError("obsolete resident dispatch table is linked")
    if args.check and any(
        symbol.name in {"OEM_Trap_Init", "MB_Map_Src", "MB_Map_Dest", "MB_Start"}
        for symbol in symbols
    ):
        raise ValueError("NOHIMEM no-op OEM hook is linked")

    by_name = {segment.name: segment for segment in segments}
    if args.check and by_name["GDT"].size > 224:
        raise ValueError("production GDT retains debugger-only descriptors")
    if args.check and by_name["_DATA"].size > 584:
        raise ValueError("EMM386 retained mutable data exceeds 584 bytes")
    symbol_by_name = {symbol.name: symbol for symbol in symbols}
    if args.check:
        mappable = symbol_by_name.get("_mappable_pages")
        count = symbol_by_name.get("_mappable_page_count")
        if (
            mappable is None
            or count is None
            or mappable.paragraph != count.paragraph
            or count.offset - mappable.offset != 52
        ):
            raise ValueError("mappable-page table is not 52 byte-sized indexes")
    text = by_name["_TEXT"]
    r_code = by_name["R_CODE"]
    segment_categories = {
        by_name["GDT"].paragraph: "retained descriptor state",
        by_name["_DATA"].paragraph: "retained mutable runtime data",
        by_name["STACK"].paragraph: "discarded initialization stack",
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
    low_text_size = split - text.offset
    if low_text_size < 0 or low_text_size > text.size:
        raise ValueError("IOTrap_Tab falls outside the linked _TEXT segment")
    if args.check:
        for name in (
            "EMM_pEntry",
            "_GetInformation",
            "_GetSetHandleName",
            "_GetHandleDirectory",
            "_GetSetHandleAttribute",
            "_GetStatus",
            "_GetPageFrameAddress",
            "_GetUnallocatedPageCount",
            "_GetEMMVersion",
            "_GetEMMHandleCount",
            "_GetEMMHandlePages",
            "_GetAllEMMHandlePages",
            "_GetMappablePAddrArrayFixed",
            "_SavePageMap",
            "_OSDisable",
            "_Get_Key_Val",
            "_UnsupportedFunction",
            "dispatch_vector",
            "int67_Entry",
            "RR_Trap_Init",
            "RRP_Handler",
            "P84_Handler",
            "P85_Handler",
            "RetRealHigh",
            "A20_Handler",
            "A20_Trap_Init",
            "get_a20_state",
            "togl_A20",
            "DisableNMI",
            "_source_addr",
            "_dest_addr",
            "_copyout",
            "_copyin",
            "_wcopy",
            "_wcopyb",
            "_valid_handle",
            "_flush_tlb",
            "_Names_Match",
            "SetDescInfoResident",
            "SegOffTo24Resident",
            "_get_pages",
            "_free_pages",
            "_AllocatePages",
            "_AllocateRawPages",
            "_DeallocatePages",
            "_ReallocatePages",
            "_MapHandlePage",
            "_RestorePageMap",
            "_GetSetPageMap",
            "_GetSetPartial",
            "_MapHandleArray",
            "_AlterMapAndJump",
            "_AlterMapAndCall",
            "_MoveExchangeMemory",
            "_AlternateMapRegisterSet",
            "Map_Lin_OEM",
            "UMap_Lin_OEM",
            "Set_Par_Vect",
            "Rest_Par_Vect",
            "Parity_Handler",
            "GoVirtualHigh",
            "AMC_return_high",
            "SelToSeg",
            "ELIM_EXE",
            "Inst_chk",
            "Inst_chk_f",
            "ELIM_link",
        ):
            if symbol_offset(symbols, name, text.paragraph) < split:
                raise ValueError(f"protected EMS service {name} remains low")
        for name in (
            "EMM_rLink",
            "RetReal",
            "RetRealResume",
            "P85Switch",
            "RRProc",
            "EnableA20",
            "DisableA20",
            "GoVirtual",
            "VM_return",
            "AMC_return_gateway",
        ):
            if symbol_offset(symbols, name, text.paragraph) >= split:
                raise ValueError(f"real-mode gateway {name} is not retained low")

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

    const = next(segment for segment in segments if segment.name == "CONST" and segment.size)
    bss = by_name["_BSS"]
    stack = by_name["STACK"]
    static_end = linear(text.paragraph, split)
    stack_start = linear(stack.paragraph, stack.offset)
    last = by_name["LAST"]
    last_end = linear(last.paragraph, last.offset) + last.size
    if args.check and stack_start < last_end:
        raise ValueError("initialization stack is not after the discardable LAST image")
    static_ranges: list[Range] = []
    cursor = 0
    retained_candidates = [
        (linear(r_code.paragraph, r_code.offset), linear(r_code.paragraph, r_code.offset) + r_code.size, "R_CODE real-mode gateway"),
        (linear(by_name["GDT"].paragraph, by_name["GDT"].offset), linear(by_name["GDT"].paragraph, by_name["GDT"].offset) + by_name["GDT"].size, "GDT descriptor state"),
        (linear(by_name["_DATA"].paragraph, by_name["_DATA"].offset), linear(by_name["_DATA"].paragraph, by_name["_DATA"].offset) + by_name["_DATA"].size, "DGROUP mutable data"),
        (linear(const.paragraph, const.offset), linear(const.paragraph, const.offset) + const.size, "DGROUP constants"),
        (linear(bss.paragraph, bss.offset), linear(bss.paragraph, bss.offset) + bss.size, "DGROUP BSS"),
        (linear(text.paragraph, text.offset), static_end, "retained/dual-mode _TEXT prefix"),
    ]
    if stack_start < static_end:
        retained_candidates.append(
            (stack_start, stack_start + stack.size, "linked stack template")
        )
    for start, end, owner in sorted(retained_candidates):
        if start > cursor:
            static_ranges.append(Range(cursor, start, "anonymous alignment gap"))
        if start < cursor:
            raise ValueError(f"overlapping retained ranges before {owner}")
        static_ranges.append(Range(start, end, owner))
        cursor = end
    if cursor != static_end:
        raise ValueError("retained static layout does not end at the _TEXT split")
    print_ranges("Retained static low-image layout", static_ranges)
    print(
        "\nThe full-depth linked initialization stack follows the discardable LAST "
        "segment and is outside the installed allocation. After VDATA compaction, "
        "the installed image places a separate 512-byte protected stack after the "
        "selected runtime-sized data."
    )

    low_text_modules: dict[str, int] = {}
    for symbol in symbols:
        if text.offset <= symbol.offset < split and symbol.paragraph == text.paragraph:
            offset = symbol.offset - text.offset
            low_text_modules.setdefault(symbol.module, offset)
            low_text_modules[symbol.module] = min(low_text_modules[symbol.module], offset)
    starts = sorted((offset, module) for module, offset in low_text_modules.items())
    text_ranges: list[Range] = []
    if not starts or starts[0][0] != 0:
        text_ranges.append(Range(0, starts[0][0], "anonymous _TEXT prefix"))
    for index, (start, module) in enumerate(starts):
        end = starts[index + 1][0] if index + 1 < len(starts) else low_text_size
        text_ranges.append(Range(start, end, display_module(module)))
    if sum(item.size for item in text_ranges) != low_text_size:
        raise ValueError("module ranges do not cover the retained _TEXT prefix")
    print_ranges("Retained `_TEXT` ranges by linked module", text_ranges)

    data_segment = by_name["_DATA"].paragraph
    data_ranges = [
        Range(0, symbol_offset(symbols, "_total_pages", data_segment), "driver state and fatal-error text"),
        Range(symbol_offset(symbols, "_total_pages", data_segment), symbol_offset(symbols, "EMM_dynamic_data_area", data_segment), "EMS runtime tables, counters, and pointers"),
        Range(symbol_offset(symbols, "EMM_dynamic_data_area", data_segment), symbol_offset(symbols, "ROM_BIOS_Machine_ID", data_segment), "OEM NMI state and alignment"),
        Range(symbol_offset(symbols, "ROM_BIOS_Machine_ID", data_segment), symbol_offset(symbols, "DMARegSav", data_segment), "OEM machine identifier and alignment"),
        Range(symbol_offset(symbols, "DMARegSav", data_segment), symbol_offset(symbols, "MB_Stat", data_segment), "DMA snapshot and page metadata"),
        Range(symbol_offset(symbols, "MB_Stat", data_segment), by_name["_DATA"].size, "move-block status and padding"),
    ]
    print_ranges("Retained `_DATA` ownership", data_ranges)

    context_pages = (args.physical_pages + 1) & ~1
    runtime_ranges: list[Range] = []
    cursor = static_end
    for size, owner in (
        (args.handles * 8, "saved LIM 3.2 maps"),
        (args.handles * 4, "handle page-index/count records"),
        (args.handles * 8, "eight-byte handle names"),
        (args.ems_pages * 2, "allocated-page index array"),
        (args.ems_pages * 2, "free-page index array"),
        (args.ems_pages * 4, "physical page-table entries"),
        (
            (args.alternate_registers + 1) * (2 + context_pages * 2),
            "normal plus alternate register sets",
        ),
    ):
        runtime_ranges.append(Range(cursor, cursor + size, owner))
        cursor += size
    if cursor - static_end > by_name["VDATA"].size:
        raise ValueError("selected runtime data exceeds linked VDATA capacity")
    aligned_stack = (cursor + 15) & ~15
    if aligned_stack > cursor:
        runtime_ranges.append(Range(cursor, aligned_stack, "installed stack alignment"))
    runtime_ranges.append(Range(aligned_stack, aligned_stack + 512, "protected stack"))
    if (
        args.check
        and (args.handles, args.alternate_registers, args.ems_pages, args.physical_pages)
        == (64, 7, 64, 4)
        and runtime_ranges[-1].end > 4304
    ):
        raise ValueError("default EMM386 installed allocation exceeds 4,304 bytes")
    print_ranges("Selected installed tail", runtime_ranges)
    print(
        f"\nSelected layout: `H={args.handles}`, `A={args.alternate_registers}`, "
        f"{args.ems_pages} EMS pages, and {args.physical_pages} mappable windows. "
        f"The computed paragraph-rounded installed allocation is "
        f"**{runtime_ranges[-1].end:,} bytes**."
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
        f"`{text.paragraph:04X}:{split:04X}`: {low_text_size:,} low bytes and "
        f"{text.size - low_text_size:,} protected-only bytes.\n"
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
