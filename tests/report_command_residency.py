#!/usr/bin/env python3
"""Report COMMAND's resident, optional-message, and discardable ranges."""

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
WORKSPACE_RE = re.compile(
    r"^COMMAND_MSG_TEMP_BUF_SZ\s+EQU\s+([0-9A-F]+H|\d+)\s*(?:;.*)?$",
    re.IGNORECASE | re.MULTILINE,
)


@dataclass(frozen=True)
class Segment:
    name: str
    start: int
    size: int

    @property
    def end(self) -> int:
        return self.start + self.size


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
                start = int(paragraph, 16) * 16 + int(offset, 16)
                segments[name] = Segment(name, start, int(size, 16))
        elif section == "symbols":
            match = SYMBOL_RE.match(raw)
            if match:
                paragraph, offset, name = match.groups()
                symbols.setdefault(name, int(paragraph, 16) * 16 + int(offset, 16))
    if not segments or not symbols:
        raise ValueError(f"could not parse segments and symbols from {path}")
    return segments, symbols


def require(mapping: dict[str, int], name: str) -> int:
    try:
        return mapping[name]
    except KeyError as error:
        raise ValueError(f"required linker symbol {name!r} is missing") from error


def rounded(value: int) -> int:
    return (value + 15) & ~15


def parse_number(value: str) -> int:
    return int(value[:-1], 16) if value.upper().endswith("H") else int(value)


def catalog_record_lengths(
    image: bytes, start: int, end: int, name: str
) -> list[int]:
    """Return length-byte-plus-payload sizes from one compiled message class."""
    file_start = start - 0x100
    file_end = end - 0x100
    if not (0 <= file_start < file_end <= len(image)):
        raise ValueError(f"{name} catalog falls outside COMMAND.COM")
    if image[file_start] != 0xFF:
        raise ValueError(f"{name} catalog has an invalid class identifier")
    count = image[file_start + 3]
    table_end = file_start + 4 + count * 4
    if table_end > file_end:
        raise ValueError(f"{name} catalog index exceeds its range")
    lengths: list[int] = []
    for index in range(count):
        entry = file_start + 4 + index * 4
        relative = int.from_bytes(image[entry + 2:entry + 4], "little")
        message = entry + relative
        if not (table_end <= message < file_end):
            raise ValueError(f"{name} catalog message pointer falls outside its range")
        record_length = image[message] + 1
        if message + record_length > file_end:
            raise ValueError(f"{name} catalog message exceeds its range")
        lengths.append(record_length)
    return lengths


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("map", type=Path, help="COMMAND linker map")
    parser.add_argument("binary", type=Path, help="COMMAND.COM built from the map")
    parser.add_argument(
        "--switches", type=Path,
        default=Path("src/CMD/COMMAND/comsw.asm"),
        help="COMMAND build switches containing its message-workspace bound",
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    segments, symbols = parse_map(args.map)
    required_segments = (
        "CODERES", "DATARES", "HMACODE", "MSGOPT", "BATARENA", "BATSEG", "ENVARENA",
        "ENVIRONMENT", "INIT", "TAIL", "TRANCODE", "TRANDATA",
        "TRANSPACE", "TRANEXT", "TRANTAIL",
    )
    missing = [name for name in required_segments if name not in segments]
    if missing:
        raise ValueError(f"required linker segments are missing: {', '.join(missing)}")

    datares_end = require(symbols, "DATARESEND")
    parse_messages = require(symbols, "parse_msg_start")
    extended_messages = require(symbols, "extended_msg_start")
    extended_end = require(symbols, "extmsgend")
    resident_state_end = require(symbols, "resmsgend")
    resident_catalog_start = require(symbols, "resident_catalog_start")
    resident_class_ptrs = require(symbols, "resident_class_ptrs")
    critical_messages = require(symbols, "critical_msg_start")
    critical_lookup = require(symbols, "$M_CLS_6")
    resident_code_end = require(symbols, "RES_CODE_END")
    hma_code_start = require(symbols, "hma_code_start")
    hma_code_end = require(symbols, "hma_code_end")
    resident_service_start = require(symbols, "ASKEND")
    disk_error_start = require(symbols, "DSKERR")
    crlf_start = require(symbols, "CRLF")
    resident_print_start = require(symbols, "RPRINT")
    kanji_gateway_start = require(symbols, "ITESTKANJ")
    reset_messages_start = require(symbols, "reset_msg_pointers")
    disk_message_start = require(symbols, "READ_DISK_PROC")
    get_message_gateway = require(symbols, "SYSGETMSG")
    display_message_gateway = require(symbols, "SYSDISPMSG")
    substitution_state_end = require(symbols, "ERRCD_24")
    pipe_state_start = require(symbols, "PIPEFILES")
    exec_state_start = require(symbols, "INPIPEPTR")
    tran_start = require(symbols, "TranStart")
    tran_data_end = require(symbols, "TRANDATAEND")
    code = segments["CODERES"]
    data = segments["DATARES"]
    errors: list[str] = []

    if code.start != 0 or data.start != code.end:
        errors.append("CODERES and DATARES are no longer contiguous at offset zero")
    if not (data.start <= resident_state_end <= resident_class_ptrs < resident_catalog_start <= critical_messages <= datares_end):
        errors.append("default resident DATARES ownership boundaries are not ordered")
    if not (resident_catalog_start <= critical_lookup < critical_messages):
        errors.append("critical-message lookup routine is not retained before its relocatable catalog")
    if rounded(resident_catalog_start) > 3632:
        errors.append("DOS-high permanent COMMAND exceeds its 3,632-byte budget")
    if rounded(hma_code_end) > 6080:
        errors.append("low/failure COMMAND fallback exceeds its 6,080-byte budget")
    if not (
        datares_end == data.end <= hma_code_start < hma_code_end
        <= parse_messages == segments["MSGOPT"].start
        <= extended_messages <= extended_end == segments["MSGOPT"].end
    ):
        errors.append("resident, HMA-code, and optional-message boundaries are not ordered")
    if not (0x100 <= resident_code_end <= code.end):
        errors.append("resident code/stack boundary falls outside CODERES")
    if not (0x100 < resident_service_start < resident_code_end):
        errors.append("resident code ownership boundaries are not ordered")
    if not (
        resident_service_start < disk_error_start < crlf_start
        < resident_print_start < kanji_gateway_start < reset_messages_start
        < disk_message_start < get_message_gateway < display_message_gateway
        < resident_code_end
    ):
        errors.append("resident error/message-service boundaries are not ordered")
    if not (
        data.start < substitution_state_end < pipe_state_start
        < exec_state_start < resident_state_end < resident_catalog_start
    ):
        errors.append("resident data ownership boundaries are not ordered")
    if tran_start != segments["TRANCODE"].start:
        errors.append("TranStart no longer equals the transient-group start")
    if tran_data_end > segments["TRANDATA"].end:
        errors.append("TRANDATAEND exceeds TRANDATA")
    if not (
        hma_code_start == segments["HMACODE"].start
        and hma_code_end == segments["HMACODE"].end
        and segments["DATARES"].end <= hma_code_start
    ):
        errors.append("HMA code boundaries do not cover the separately releasable segment")
    image = args.binary.read_bytes()
    image_end = len(image) + 0x100
    if image_end != segments["TRANEXT"].end:
        errors.append("binary size plus the PSP origin no longer equals the initialized image end")

    workspace_match = WORKSPACE_RE.search(args.switches.read_text(encoding="latin-1"))
    if not workspace_match:
        raise ValueError(f"COMMAND message-workspace bound is missing from {args.switches}")
    workspace_size = parse_number(workspace_match.group(1))
    catalog_lengths = []
    for name, start, end in (
        ("critical", critical_messages, datares_end),
        ("parse", parse_messages, extended_messages),
        ("extended", extended_messages, extended_end),
    ):
        catalog_lengths.extend(catalog_record_lengths(image, start, end, name))
    largest_record = max(catalog_lengths)
    if largest_record > workspace_size:
        errors.append(
            f"largest disk-loaded message record ({largest_record} bytes) exceeds "
            f"the COMMAND workspace ({workspace_size} bytes)"
        )

    print("# COMMAND residency census\n")
    print("## Default resident image\n")
    print("| Range | Offset | Bytes | Owner/lifetime |")
    print("| --- | ---: | ---: | --- |")
    ranges = [
        ("PSP and command tail", 0, 0x100, "DOS process ABI; resident"),
        ("Resident code", 0x100, resident_code_end, "EXEC/reload, INT 22h/23h/24h/2Eh, messages; resident"),
        ("Resident stack", resident_code_end, code.end, "asynchronous and reload paths; resident"),
        ("Mutable shell state", data.start, resident_state_end, "batch, pipe, environment, EXEC, reload; resident"),
        ("Resident message runtime data", resident_state_end, resident_catalog_start, "mutable formatter and far class pointers"),
        ("Utility-message catalogs", resident_catalog_start, critical_messages, "HMA for permanent DOS-high shell; low fallback otherwise"),
        ("Critical-error messages", critical_messages, datares_end, "same HMA payload; low fallback otherwise"),
    ]
    for name, start, end, owner in ranges:
        print(f"| {name} | `{start:04X}h..{end:04X}h` | {end - start:,} | {owner} |")
    print(f"| **DOS-high permanent break** | `0000h..{resident_catalog_start:04X}h` | **{resident_catalog_start:,}** | **{rounded(resident_catalog_start):,} paragraph-rounded** |")
    print(f"| Low/failure fallback break | `0000h..{hma_code_end:04X}h` | {hma_code_end:,} | {rounded(hma_code_end):,} paragraph-rounded |")

    print("\n## Permanent low ownership\n")
    print("| Range | Offset | Bytes | Required lifetime |")
    print("| --- | ---: | ---: | --- |")
    permanent_low = [
        ("Entry, EXEC, reload, and interrupt paths", 0x100, resident_service_start,
         "survives transient overwrite and asynchronous entry"),
        ("Resident error and message services", resident_service_start, resident_code_end,
         "batch abort, INT 24h, and message display"),
        ("Resident stack", resident_code_end, code.end,
         "nested asynchronous and reload paths"),
        ("Message substitutions and critical-error state", data.start, substitution_state_end,
         "mutable formatter inputs and INT 24h state"),
        ("Shell, batch, and load-high control state", substitution_state_end, pipe_state_start,
         "persistent interpreter control state"),
        ("Pipe path and hand-off state", pipe_state_start, exec_state_start,
         "survives both sides of pipeline EXEC/reload"),
        ("EXEC, environment, and transient-image state", exec_state_start, resident_state_end,
         "reload and child-shell bookkeeping"),
        ("Mutable message runtime", resident_state_end, resident_catalog_start,
         "formatter workspace and five far class slots"),
    ]
    for name, start, end, lifetime in permanent_low:
        print(f"| {name} | `{start:04X}h..{end:04X}h` | {end - start:,} | {lifetime} |")

    print("\n## Resident error and message services\n")
    print("| Range | Offset | Bytes | Required lifetime |")
    print("| --- | ---: | ---: | --- |")
    resident_services = [
        ("Batch-termination prompt", resident_service_start, disk_error_start,
         "resident caller after transient teardown"),
        ("Critical-error handler", disk_error_start, crlf_start,
         "installed INT 24h target; asynchronous DOS and redirector entry"),
        ("CR/LF entry", crlf_start, resident_print_start,
         "shared resident display entry"),
        ("Resident message-print wrapper", resident_print_start, kanji_gateway_start,
         "resident fatal, batch, EXEC, and critical-error callers"),
        ("DBCS test gateway", kanji_gateway_start, reset_messages_start,
         "low/failure entry; permanent root body is in HMA"),
        ("Message-pointer reset", reset_messages_start, disk_message_start,
         "child and fatal-exit cleanup"),
        ("Disk-backed message callback", disk_message_start, get_message_gateway,
         "registered DOS callback and INT 24h disk-error path"),
        ("GET-message gateway", get_message_gateway, display_message_gateway,
         "near fallback; patched to far call only in permanent root"),
        ("DISPLAY-message gateway", display_message_gateway, resident_code_end,
         "near fallback; patched to far call only in permanent root"),
    ]
    for name, start, end, lifetime in resident_services:
        print(f"| {name} | `{start:04X}h..{end:04X}h` | {end - start:,} | {lifetime} |")

    print("\n## Optional and discardable ranges\n")
    print("| Range | Offset | Bytes | Lifetime |")
    print("| --- | ---: | ---: | --- |")
    optional = [
        ("Relocatable resident code", hma_code_start, hma_code_end,
         "HMA for permanent DOS-high shell; low fallback otherwise"),
        ("Parse-error catalog", parse_messages, extended_messages, "resident only with `/MSG`"),
        ("Extended-error catalog", extended_messages, extended_end, "resident only with `/MSG`"),
        ("Batch arena header", segments["BATARENA"].start, segments["BATARENA"].end, "runtime allocation template"),
        ("Initial batch block", segments["BATSEG"].start, segments["BATSEG"].end, "runtime allocation template"),
        ("Environment arena header", segments["ENVARENA"].start, segments["ENVARENA"].end, "runtime allocation template"),
        ("Initial environment", segments["ENVIRONMENT"].start, segments["ENVIRONMENT"].end, "moved to its own allocation"),
        ("Initialization", segments["INIT"].start, segments["INIT"].end, "discarded after startup"),
        ("Reloadable transient", tran_start, image_end, "overwritable and reloaded after EXEC"),
    ]
    for name, start, end, lifetime in optional:
        print(f"| {name} | `{start:04X}h..{end:04X}h` | {end - start:,} | {lifetime} |")
    print(f"\n`/MSG` retains all catalogs and raises the DOS-high permanent break by "
          f"{rounded(extended_end) - rounded(resident_catalog_start):,} bytes to "
          f"{rounded(extended_end):,} paragraph-rounded bytes.")
    print(
        f"The largest disk-loaded catalog record is {largest_record} bytes; "
        f"COMMAND's checked message workspace is {workspace_size} bytes."
    )

    if errors:
        print("\n## Census errors\n")
        for error in errors:
            print(f"- {error}")
    return 1 if args.check and errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
