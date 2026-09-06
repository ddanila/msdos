#!/usr/bin/env python3
"""Report COMMAND's resident, optional-message, and discardable ranges."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import subprocess


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


def code_only_envelope(code_end: int, resident_break: int, service_start: int = 0x100) -> tuple[int, int]:
    """Optimistic packed low floor and release, before any new support.

    Preserve PSP, any entry block before service_start, and all non-code bytes.
    This is a design bound, not evidence that the body is relocatable.
    """
    if not 0x100 <= service_start <= code_end <= resident_break:
        raise ValueError("resident code must follow the PSP and precede the break")
    low_floor = rounded(resident_break - (code_end - service_start))
    return low_floor, rounded(resident_break) - low_floor


BINDING_SLOTS = ("fatal_ds", "fatal_psp", "ret2e_ds", "int2e_es", "int2e_bx",
                 "lodcom_ds", "lodcom_ax", "headfix_ds", "savhand_es", "endinit_ds",
                 "exec_err_ds", "exec_msg_es", "exec_pre_ds", "exec_post_ds", "exec_wait_ds",
                 "critical_es", "critical_ds", "contc_entry_ds", "contc_body_ds", "pipeoff_ds")

GATE_TARGETS = (("lodcom", "lodcom"), ("contc", "CONTC"), ("dskerr", "DSKERR"),
                ("int2e", "INT_2E"), ("headfix", "THEADFIX"), ("exec", "EXT_EXEC"),
                ("remcheck", "TREMCHECK"), ("diskmsg", "READ_DISK_PROC"))

BRIDGE_TARGETS = (("init", "init_contc_specialcase"), ("xlat", "hma_in_char_xlat_high"),
                  ("kanj", "hma_test_kanj_high"), ("getmsg", "shell_getmsg_fallback"),
                  ("dispmsg", "shell_dispmsg_fallback"))


def check_relative_service_branches(disassembly: str, start: int, end: int) -> None:
    for line in disassembly.splitlines():
        branch = re.match(r"^[0-9A-F]+\s+[0-9A-F]+\s+(?:j\w+|call|loop\w*)\s+(?:near |short )?0x([0-9a-f]+)$", line, re.I)
        if branch and not start <= int(branch[1], 16) < end:
            raise ValueError(f"relative service branch escapes the movable body: {line}")


def check_shell_bridges(symbols: dict[str, int], image: bytes) -> None:
    start, end = require(symbols, "shell_service_start"), require(symbols, "RES_CODE_END")
    constructor = bytearray()
    for slot, target in BRIDGE_TARGETS:
        bridge = require(symbols, "shell_bridge_" + slot)
        segment = require(symbols, "shell_bridge_" + slot + "_segment")
        opcode = 0xEA if slot == "init" else 0x9A
        expected = bytes((opcode,)) + require(symbols, target).to_bytes(2, "little") + b"\0\0"
        if (not start <= bridge <= end - 5 or segment != bridge + 3
                or image[bridge-0x100:bridge-0xFB] != expected):
            raise ValueError("outgoing service bridge lacks its bound far transfer")
        constructor.extend(b"\x8c\x0e" + segment.to_bytes(2, "little"))
    init = require(symbols, "shell_bridge_constructor")
    if (init != require(symbols, "shell_gate_constructor_end")
            or require(symbols, "shell_bridge_constructor_end") != init + len(constructor)
            or image[init-0x100:init-0x100+len(constructor)] != constructor):
        raise ValueError("outgoing bridge constructor is incomplete or misplaced")
    for slot, engine in (("getmsg", "HMA_SYSGETMSG"), ("dispmsg", "HMA_SYSDISPMSG")):
        wrapper = require(symbols, "shell_" + slot + "_fallback")
        displacement = (require(symbols, engine) - wrapper - 3) & 0xFFFF
        if image[wrapper-0x100:wrapper-0xFC] != b"\xe8" + displacement.to_bytes(2, "little") + b"\xcb":
            raise ValueError("message fallback must adapt a near engine to a far return")
    decoded = subprocess.run(["ndisasm", "-b16", f"-o{start}", "-"],
                             input=image[start-0x100:end-0x100], capture_output=True, check=True)
    check_relative_service_branches(decoded.stdout.decode(), start, end)


def check_shell_gates(symbols: dict[str, int], image: bytes) -> None:
    start = require(symbols, "shell_gate_start")
    end = require(symbols, "shell_service_start")
    if start != 0x103 or end - start != 5 * len(GATE_TARGETS):
        raise ValueError("published gate island must immediately follow the startup jump")
    constructor = bytearray()
    for index, (slot, target) in enumerate(GATE_TARGETS):
        gate = require(symbols, "shell_gate_" + slot)
        segment = require(symbols, "shell_gate_" + slot + "_segment")
        destination = require(symbols, target)
        if not end <= destination < require(symbols, "RES_CODE_END"):
            raise ValueError("gate target is not in the complete resident service body")
        expected = b"\xea" + destination.to_bytes(2, "little") + b"\0\0"
        if (gate != start + index * 5 or segment != gate + 3
                or image[gate - 0x100:gate - 0x100 + 5] != expected):
            raise ValueError("published gate lacks its exact five-byte far jump")
        constructor.extend(b"\x8c\x0e" + segment.to_bytes(2, "little"))
    init = require(symbols, "shell_gate_constructor")
    if (init != require(symbols, "CONPROC") + 3 + 4 * len(BINDING_SLOTS)
            or require(symbols, "shell_gate_constructor_end") != init + len(constructor)
            or image[init - 0x100:init - 0x100 + len(constructor)] != constructor):
        raise ValueError("gate constructor must follow owner bindings before publication")
    for offset, slot in ((0, "headfix"), (8, "exec"), (12, "remcheck")):
        pos = require(symbols, "TRANVARS") + offset - 0x100
        if image[pos:pos + 2] != require(symbols, "shell_gate_" + slot).to_bytes(2, "little"):
            raise ValueError("transient publication bypasses a stable low gate")


def check_resident_bindings(symbols: dict[str, int], image: bytes) -> None:
    expected = {"shell_binding_" + name for name in BINDING_SLOTS}
    if {name for name in symbols if name.startswith("shell_binding_")} != expected:
        raise ValueError("resident binding slots differ from the constructor contract")
    constructor = bytearray()
    for name in BINDING_SLOTS:
        offset = symbols["shell_binding_" + name]
        if not 0x101 <= offset < require(symbols, "RES_CODE_END") - 1:
            raise ValueError("resident binding is outside the service body")
        opcode = 0xBB if name == "int2e_bx" else 0xB8
        if image[offset-0x101:offset-0xFE] != bytes((opcode, 0, 0)):
            raise ValueError("resident binding is not a zero-initialized immediate operand")
        constructor.extend(b"\x8c\x0e" + offset.to_bytes(2, "little"))
    start = require(symbols, "CONPROC") - 0x100 + 3  # MOV SP,RSTACK first
    if image[start:start+len(constructor)] != constructor:
        raise ValueError("resident binding constructor does not initialize every operand")


def check_critical_owner_bindings(symbols: dict[str, int], image: bytes) -> None:
    """Check AX preservation, driver DS lifetime, and the first shell store."""
    for name, segment_opcode in (("critical_es", 0xC0), ("critical_ds", 0xD8)):
        operand = require(symbols, "shell_binding_" + name)
        start = operand - 0x102
        expected = b"\x50\xb8\0\0\x8e" + bytes((segment_opcode,)) + b"\x58"
        if name == "critical_es":
            # MOV ES:[CDEVAT],AH, not CS (relocated code) or DS (driver).
            expected += b"\x26\x88\x26" + require(symbols, "CDEVAT").to_bytes(2, "little")
        if image[start:start + len(expected)] != expected:
            raise ValueError("critical entry lost its explicit low owner or AX preservation")


def check_code_owner_listing(listing: str) -> None:
    """Reject assembled CS overrides, including implicit ASSUME selections.

    This is a guard for the selected service modules, not an x86 decoder or
    proof that near calls, far publications and state bindings are relocatable.
    """
    prefixes = {0x26, 0x2E, 0x36, 0x3E, 0x64, 0x65, 0x66, 0x67, 0xF0, 0xF2, 0xF3}
    found = False
    for line in listing.splitlines():
        match = re.match(r"^\s*[0-9A-F]{4,8}\s+([0-9A-F]{2}(?:[0-9A-F]{2})*)(?=\s|$)", line, re.I)
        if not match:
            continue
        found = True
        for byte in bytes.fromhex(match[1]):
            if byte not in prefixes:
                break
            if byte == 0x2E:
                raise ValueError(f"service listing still addresses state through CS: {line.strip()}")
    if not found:
        raise ValueError("no assembled bytes found in service listing")


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
    parser.add_argument("--resident-binding", action="store_true",
                        help="check the development resident owner operands and constructor")
    parser.add_argument("--binding-listings", nargs=3, type=Path,
                        help="check COMMAND1, COMMAND2 and RUCODE development listings for CS overrides")
    parser.add_argument("--gate-include", type=Path,
                        help="write NASM constants for the development live-publication probe")
    parser.add_argument("--critical-split", action="store_true",
                        help="check the development low-entry/body/exit layout (body still low)")
    parser.add_argument("--critical-reclaim", action="store_true",
                        help="check development startup relocation of the body from HMACODE")
    args = parser.parse_args()
    if args.gate_include and not args.resident_binding:
        parser.error("--gate-include requires --resident-binding")
    if args.binding_listings:
        if not args.resident_binding:
            parser.error("--binding-listings requires --resident-binding")
        if [path.stem.upper() for path in args.binding_listings] != ["COMMAND1", "COMMAND2", "RUCODE"]:
            parser.error("supply COMMAND1, COMMAND2 and RUCODE listings in that order")
        for path in args.binding_listings:
            check_code_owner_listing(path.read_text(encoding="latin-1"))
    if args.critical_reclaim:
        args.critical_split = True
    if args.resident_binding and args.critical_split:
        parser.error("combined binding/critical prototype is not yet qualified")

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
    resident_critical_ptr = require(symbols, "resident_critical_ptr")
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
    if not (resident_state_end <= resident_critical_ptr
            and resident_critical_ptr + 4 <= resident_class_ptrs):
        errors.append("cached critical-catalog pointer is not retained in low message state")
    prototype_allowance = 128 if args.critical_split else 0
    fallback_allowance = prototype_allowance
    if args.resident_binding:
        prototype_allowance = 128
        fallback_allowance = 144
        check_resident_bindings(symbols, args.binary.read_bytes())
        check_critical_owner_bindings(symbols, args.binary.read_bytes())
        check_shell_gates(symbols, args.binary.read_bytes())
        check_shell_bridges(symbols, args.binary.read_bytes())
        if args.gate_include:
            constants = ["%define EXPECT_SHELL_GATES 1",
                         f"%define SHELL_TRANVARS {require(symbols, 'TRANVARS')}"]
            for slot, _ in GATE_TARGETS:
                constants.append(f"%define SHELL_GATE_{slot.upper()} {require(symbols, 'shell_gate_' + slot)}")
            constants.append("%define SHELL_GATE_TARGETS " + ",".join(
                str(require(symbols, target)) for _, target in GATE_TARGETS))
            constants.append("%define EXPECT_SHELL_BRIDGES 1")
            for slot, target in BRIDGE_TARGETS:
                constants.append(f"%define SHELL_BRIDGE_{slot.upper()} {require(symbols, 'shell_bridge_' + slot)}")
                constants.append(f"%define SHELL_FALLBACK_{slot.upper()} {require(symbols, target)}")
            for slot, pointer in (("XLAT", "hma_in_char_xlat_entry"), ("KANJ", "hma_test_kanj_entry")):
                constants.append(f"%define SHELL_POINTER_{slot} {require(symbols, pointer)}")
            for slot, engine in (("GETMSG", "HMA_SYSGETMSG"), ("DISPMSG", "HMA_SYSDISPMSG")):
                constants.append(f"%define SHELL_DELTA_{slot} {require(symbols, engine) - require(symbols, 'hma_in_char_xlat_high')}")
            args.gate_include.write_text("\n".join(constants) + "\n")
    if rounded(resident_catalog_start) > 3632 + prototype_allowance:
        errors.append(f"DOS-high permanent COMMAND exceeds its {3632 + prototype_allowance:,}-byte budget")
    if rounded(hma_code_end) > 6080 + fallback_allowance:
        errors.append(f"low/failure COMMAND fallback exceeds its {6080 + fallback_allowance:,}-byte budget")
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
    if args.critical_split:
        body_start = require(symbols, "critical_body_start")
        body_end = require(symbols, "critical_body_end")
        dispatch = require(symbols, "critical_dispatch")
        constructor = require(symbols, "critical_constructor_start")
        constructor_end = require(symbols, "critical_constructor_end")
        if not (constructor == require(symbols, "CONPROC") + 3
                and segments["INIT"].start <= constructor < constructor_end <= segments["INIT"].end):
            errors.append("critical binding constructor is not at the discardable initialization entry")
        exits = [require(symbols, name) for name in (
            "critical_return_low", "critical_reload_low",
            "critical_terminate_low", "critical_dead_low",
        )]
        low_interface_end = crlf_start if args.critical_reclaim else body_start
        if not (disk_error_start < exits[0] < exits[1] < exits[2]
                < exits[3] < low_interface_end):
            errors.append("development critical entry, exits and body are not separated")
        if args.critical_reclaim:
            if not (body_start == hma_code_start < body_end <= hma_code_end):
                errors.append("reclaimable critical body is not inside the HMA code allocation")
        elif body_end != crlf_start:
            errors.append("unreclaimed critical body does not end at CRLF")
        expected_dispatch = (b"\xe9" + ((body_start - dispatch - 3) & 0xFFFF).to_bytes(2, "little")
                             + b"\x90\x90")
        if not (dispatch + 5 == exits[0]
                and image[dispatch - 0x100:dispatch - 0x100 + 5] == expected_dispatch):
            errors.append("development critical dispatch lacks its five-byte publication window")
        for name, opcode, size in [
            (name, 0x9A, 6) for name in (
                "CRLF", "RPRINT", "SYSGETMSG", "TestKanjR",
                "IN_CHAR_XLAT", "ResPipeOff", "int21", "int2f",
            )
        ] + [(name, 0xEA, 5) for name in ("return", "reload", "terminate", "dead")]:
            bridge = require(symbols, f"critical_{name}_bridge")
            binding = require(symbols, f"critical_{name}_segment")
            target = require(symbols, f"critical_{name}_low")
            expected = bytes([opcode]) + target.to_bytes(2, "little") + b"\0\0"
            if opcode == 0x9A:
                expected += b"\xc3"
            if not (body_start <= bridge < bridge + size <= body_end
                    and binding == bridge + 3
                    and disk_error_start <= target < low_interface_end
                    and image[bridge - 0x100:bridge - 0x100 + size] == expected):
                errors.append(f"development critical {name} bridge has an invalid far binding")
        print(f"| Development critical entry and exits | `{disk_error_start:04X}h..{low_interface_end:04X}h` | {low_interface_end - disk_error_start:,} | low interfaces |")
        placement = "startup HMA relocation; low fallback" if args.critical_reclaim else "still low; test-loader relocation only"
        print(f"| Development complete critical body | `{body_start:04X}h..{body_end:04X}h` | {body_end - body_start:,} | {placement}; A20 return gates pending |")
        print(f"| Critical binding constructor | `{constructor:04X}h..{constructor_end:04X}h` | {constructor_end - constructor:,} | discardable initialization |")
        print("\nDevelopment only: the 128-byte temporary support allowance is not")
        print("a production budget increase or a claimed conventional-memory saving.\n")
    print(f"| **DOS-high permanent break** | `0000h..{resident_catalog_start:04X}h` | **{resident_catalog_start:,}** | **{rounded(resident_catalog_start):,} paragraph-rounded** |")
    print(f"| Low/failure fallback break | `0000h..{hma_code_end:04X}h` | {hma_code_end:,} | {rounded(hma_code_end):,} paragraph-rounded |")

    service_start = require(symbols, "shell_service_start") if args.resident_binding else 0x100
    low_floor, maximum_release = code_only_envelope(resident_code_end, resident_catalog_start, service_start)
    print("\n## Whole-code relocation bound\n")
    if args.resident_binding:
        print(f"The published low entry block is 40 bytes at 0103h..012Bh; "
              f"the service body starts at {service_start:04X}h. "
              "The bound below retains that block and the startup jump.\n")
    print(f"Moving all {resident_code_end - service_start:,} remaining resident service bytes, "
          f"while retaining the PSP, stack and all mutable state, leaves at least "
          f"{low_floor:,} paragraph-rounded low bytes. The optimistic release is "
          f"at most {maximum_release:,} bytes before new gateways, bindings or stacks.")
    print("This assumes packed low storage with no retained code hole. Separate "
          "environment/batch allocations are unchanged; existing high catalogs "
          "and code earn no additional credit. This is not a linked relocated "
          "implementation or a measured saving.")

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
