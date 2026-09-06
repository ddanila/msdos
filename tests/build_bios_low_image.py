#!/usr/bin/env python3
"""Link an inactive, relocation-capable BIOS without replacing normal IO.SYS."""
from pathlib import Path
import argparse
import hashlib
import json
import runpy
import re
import subprocess
import sys

from build_bios_high_payload import ROOT, run
from report_dos_bios_residency import parse_map


def build(output, *, early=False, reservation_limit=0xfff0, tail_body=False, scan=False, rebase=False, compact=False, fail_tables=False, high_cds=False, fail_cds=False, cds_cache_case=None, cds_cache_negative=False, dispatch=False, characters=False, paired_provider=None):
    if paired_provider is not None and not (early and rebase and compact):
        raise ValueError("paired provider requires the early rebased/compacted composition")
    if characters and not dispatch:
        raise ValueError("character owner requires far dispatch tables")
    cache_cases = {"first": 1, "last": 2, "past-end": 3, "foreign": 4}
    if cds_cache_case is not None and (not high_cds or cds_cache_case not in cache_cases):
        raise ValueError("CDS cache case requires high CDS and a known case")
    if cds_cache_negative and (cds_cache_case not in ("first", "last") or fail_cds):
        raise ValueError("negative CDS cache control requires a relocating first/last case")
    if high_cds and not rebase:
        raise ValueError("high CDS requires the development rebased layout")
    if fail_cds and not high_cds:
        raise ValueError("CDS allocation failure requires high CDS")
    if fail_tables and not rebase:
        raise ValueError("table allocation failure control requires rebasing")
    if compact and not rebase:
        raise ValueError("arena compaction requires low-prefix rebasing")
    if (scan or rebase) and not (early and tail_body):
        raise ValueError("pointer census/rebase requires the early tail-body layout")
    if not 0 <= reservation_limit <= 0xfff0:
        raise ValueError("invalid development reservation ceiling")
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if paired_provider is not None:
        from emm_loader_rebase import include as rebase_include
        (output / "PROVIDERFIXUPS.INC").write_text(rebase_include(Path(paired_provider).read_bytes()))
    run([sys.executable, ROOT / "tools/gen_dos_copy_size.py",
         ROOT / "src/DOS/MSDOS.SYS", output / "DOSCOPY.INC"], ROOT)
    embedded = None
    if early:
        from build_bios_high_payload import build as build_high
        from build_bios_activation_fixture import write_fixture
        seed = build(output, tail_body=tail_body, dispatch=dispatch, characters=characters)
        if rebase:
            _, dos_symbols = parse_map(ROOT / "src/DOS/MSDOS.MAP")
            dos_symbols = {name.upper(): value for name, value in dos_symbols.items()}
            if high_cds:
                (output / "CDSUPPER_DEFS.INC").write_text(
                    f"CDS_THISCDS EQU {dos_symbols['THISCDS']}\n")
            names = {"LOW_OWNER": "HMA_LOW_SEGMENT", "LOW_END": "DOS_LOW_GATE_END",
                     "INDOS": "INDOS", "DRIVER_ENTRY": "HMA_DRIVER_TRAMPOLINE_ENTRY",
                     "LOW_DPBS": "HMA_LOW_DPBS", "CDSCOUNT": "CDSCOUNT", "CDSADDR": "CDSADDR",
                     "ARENA_HEAD": "ARENA_HEAD"}
            definitions = {name: dos_symbols[symbol] for name, symbol in names.items()}
            definitions.update({"PERMANENT_END": seed["symbols"]["BIOS_PERMANENT_END"],
                                "FROM": seed["symbols"]["BIOS_REBASED_FROM"],
                                "TO": seed["symbols"]["BIOS_REBASED_TO"],
                                "PTRSAV": seed["symbols"]["PTRSAV"],
                                "LOW_PARAS": (definitions["LOW_END"] + 15) // 16})
            # Declared far pointers only; do not derive fixups from scan matches.
            fields = [(name, 2) for name in (
                "DPBHEAD", "sft_addr", "BCLOCK", "BCON", "BUFFHEAD", "CDSADDR",
                "sftFCB", "NULDEV", "IFS_DOS_CALL", "IFS_HEADER", "BUF_HASH_PTR",
                "SC_CACHE_PTR", "LastBuffer", "SysInitTable", "CurHashEntry",
                "SWAP_IN_DOS", "SWAP_ALWAYS_AREA", "IFSFUNC_SWAP_IN_DOS",
                "EXTERRPT", "DMAADD", "CALLVIDRW", "CALLXAD", "CALLDEVAD", "IOXAD",
                "EXITHOLD", "THISDPB", "DEVPT", "THISSFT", "THISCDS", "THISFCB",
                "PJFN", "CURBUF", "CONSft")]
            fields += [("DSKCHRET", 3), ("SysInitTable", 6)]
            offsets = [dos_symbols[name.upper()] + delta for name, delta in fields]
            if any(offset + 2 > definitions["LOW_END"] for offset in offsets):
                raise ValueError("declared low-pointer field outside low prefix")
            definitions["FIELD_COUNT"] = len(offsets)
            (output / "BIOSREBASE_DEFS.INC").write_text("".join(
                f"RB_{name} EQU {value}\n" for name, value in definitions.items()))
            (output / "BIOSREBASE_FIELDS.INC").write_text("".join(
                f"dw {offset} ; {name}+{delta}\n" for offset, (name, delta) in zip(offsets, fields)))
        if scan:
            _, dos_symbols = parse_map(ROOT / "src/DOS/MSDOS.MAP")
            scan_symbols = {"LOW_SEGMENT": dos_symbols["hma_low_segment"],
                            "LOW_END": dos_symbols["DOS_LOW_GATE_END"],
                            "HIGH_END": dos_symbols["SYSBUF"],
                            "CDSCOUNT": dos_symbols["CDSCOUNT"],
                            "CDSADDR": dos_symbols["CDSADDR"],
                            "PERMANENT_END": seed["symbols"]["BIOS_PERMANENT_END"]}
            (output / "BIOSSCAN_DEFS.INC").write_text("".join(
                f"SCAN_{name} EQU {value}\n" for name, value in scan_symbols.items()))
        high = build_high(output / "high", output, dispatch=dispatch, characters=characters)
        write_fixture(output, seed, high)
        for source, target in (("defs", "DEFS"), ("preflight", "PREFLIGHT"),
                               ("bind-high", "BIND_HIGH"), ("bind-low", "BIND_LOW"),
                               ("data", "DATA")):
            text = (output / f"activation-{source}.inc").read_text()
            text = re.sub(r"\[(es|cs):([^\]]+)\]", r"\1:[\2]", text)
            text = re.sub(r"\b(byte|word) (?=(?:es:|cs:)?\[)", r"\1 ptr ", text)
            text = re.sub(r"mov si,(activation_original_\d+)", r"mov si,OFFSET \1", text)
            text = re.sub(r"\bfail\b", "BiosBootFail", text)
            if source == "data":
                lines = []
                for line in text.splitlines():
                    if line.startswith("dw "):
                        values = line[3:].split(",")
                        lines.extend("dw " + ",".join(values[index:index + 16])
                                     for index in range(0, len(values), 16))
                    else:
                        lines.append(line)
                text = "\n".join(lines) + "\n"
            if source == "defs":
                text += f"ACTIVE_OFFSET equ {seed['symbols']['BIOS_SERVICE_ACTIVE']}\n"
                text += f"BOOT_PAYLOAD_BYTES equ {high['bytes']}\n"
                text += f"BOOT_RESERVATION_LIMIT equ {reservation_limit}\n"
            (output / f"BIOSBOOT_{target}.INC").write_text(text)
        embedded = (output / "high/bios-high.bin").read_bytes()
        (output / "BIOSBOOT_PAYLOAD.INC").write_text("\n".join(
            "db " + ",".join(map(str, embedded[index:index + 16]))
            for index in range(0, len(embedded), 16)) + "\n")
    bios = ROOT / "src/BIOS"
    changed = ("MSBIO1", "MSDISK", "MSBIO2") + (("MSINIT", "SYSINIT1", "SYSCONF") if early else ())
    if tail_body and not early:
        changed += ("MSINIT",)
    options = "-I. -I../INC " + " ".join(f"-DBIOS_SERVICE_{name}=1" for name in
        ("BINDINGS", "LOW_CALLS", "DEVICE_ENTRIES", "INTERRUPT_ENTRIES", "RESULT_HELPERS"))
    if early:
        options += f" -I{output} -DBIOS_SERVICE_BOOT=1 -DBIOS_BOOT_POISON=1"
    if paired_provider is not None:
        options += (" -DBIOS_DYNAMIC_STAGING -DBIOS_DEFER_PROVIDER -DPROVIDER_REBASE"
                    " -DBIOS_STAGE_PROVIDER -DBIOS_PROVIDER_DOWN -DBIOS_ADMIN_PROVIDER")
    if tail_body:
        options += " -DBIOS_SERVICE_TAIL_BODY=1"
    if dispatch:
        options += " -DBIOS_SERVICE_DISPATCH=1"
    if scan:
        options += " -DBIOS_BOOT_SCAN=1"
    if rebase:
        options += " -DBIOS_BOOT_REBASE=1"
    if high_cds:
        options += " -DBIOS_HIGH_CDS=1"
    if fail_cds:
        options += " -DBIOS_CDS_FAIL_ALLOC=1"
    if cds_cache_case:
        options += f" -DBIOS_CDS_CACHE_CASE={cache_cases[cds_cache_case]}"
    if cds_cache_negative:
        options += " -DBIOS_CDS_SKIP_CACHE_REBASE=1"
    if fail_tables:
        options += " -DBIOS_TABLES_FAIL_ALLOC=1"
    if compact:
        options += " -DBIOS_BOOT_COMPACT=1"
    for name in changed:
        object_options = options
        if tail_body and name == "MSDISK":
            object_options += " -DBIOS_SERVICE_PREFIX_ONLY=1"
        run([ROOT / "bin/jwasm-masm", object_options,
             f"{name}.ASM,{output / (name + '.OBJ')};"], bios)
    names = ("MSBIO1", "MSCON", "MSAUX", "MSLPT", "MSCLOCK", "MSDISK", "MSBIO2",
             "MSHARD", "MSINIT", "SYSINIT1", "SYSCONF", "SYSINIT2", "SYSIMES")
    objects = [(output if name in changed else bios) / (name + ".OBJ") for name in names]
    if tail_body:
        body = output / "BIOBODY.OBJ"
        run([ROOT / "bin/jwasm-masm", options + " -DBIOS_SERVICE_BODY_ONLY=1",
             f"MSDISK.ASM,{body};"], bios)
        objects.append(body)
    executable, linked_map = output / "MSBIO.EXE", output / "msBIO.map"
    linker = runpy.run_path(str(ROOT / "bin/wlink"))["wlink_bin"]()
    run([linker, "format", "dos", "option", "quiet", "option", "nocaseexact",
         "option", "nofarcalls", "option", f"map={linked_map}", "name", executable,
         *[arg for obj in objects for arg in ("file", obj)]], bios)
    binary = output / "MSBIO.BIN"
    subprocess.run([ROOT / "bin/exe2bin", executable, binary], input=b"70\n", check=True)
    image = (bios / "MSLOAD.COM").read_bytes() + binary.read_bytes()
    (output / "IO.SYS").write_bytes(image)
    _, symbols = parse_map(linked_map)
    symbols = {name.upper(): value for name, value in symbols.items()}
    if tail_body:
        if symbols["BIOS_SERVICE_START"] < symbols["END$"]:
            raise ValueError("fallback service body is not after BIOS initialization code")
        if symbols["BIOS_PERMANENT_END"] >= symbols["BIOS_SERVICE_START"]:
            raise ValueError("permanent boundary storage overlaps fallback service body")
    active = symbols["BIOS_SERVICE_ACTIVE"]
    if binary.read_bytes()[active] != 0:
        raise ValueError("development BIOS starts active with unbound targets")
    near_words = {"BIOS_HIGH_SETDRIVE", "BIOS_HIGH_MAPERROR", "BIOS_HIGH_READ_SECTOR",
                  "BIOS_HIGH_CHECKSINGLE"}
    slot_words = []
    for name, offset in symbols.items():
        if name.startswith("BIOS_HIGH_"):
            slot_words += [offset] if name in near_words else [offset, offset + 2]
    data = binary.read_bytes()
    if not slot_words or any(data[offset:offset + 2] != b"\0\0" for offset in slot_words):
        raise ValueError("inactive high import slots must be zero")
    manifest = {"activated": False, "reclaimed_bytes": 0,
                "sha256": hashlib.sha256(image).hexdigest(), "symbols": symbols,
                "high_slot_words": sorted(slot_words), "early_boot_installer": early,
                "reservation_limit": reservation_limit, "tail_body": tail_body, "dispatch": dispatch, "characters": characters,
                "pointer_census": scan, "low_prefix_rebase": rebase, "arena_compaction": compact,
                "high_cds": high_cds, "fail_cds": fail_cds}
    if early:
        # Init-segment growth must not invalidate any embedded low operands.
        for name, value in seed["symbols"].items():
            if name in high["low_bindings"] or name.startswith("BIOS_") or name == "DSKTBL":
                if symbols[name] != value:
                    raise ValueError(f"early link moved embedded low binding: {name}")
        final_high = build_high(output / "high", output, dispatch=dispatch, characters=characters)
        if (output / "high/bios-high.bin").read_bytes() != embedded:
            raise ValueError("early link changed the embedded high payload")
        manifest["embedded_payload_bytes"] = final_high["bytes"]
    manifest["upper_dos_tables"] = rebase
    manifest["paired_provider_sha256"] = (hashlib.sha256(Path(paired_provider).read_bytes()).hexdigest()
                                          if paired_provider is not None else None)
    manifest["cds_cache_case"] = cds_cache_case
    manifest["cds_cache_negative"] = cds_cache_negative
    manifest["force_table_allocation_failure"] = fail_tables
    (output / "low.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"Linked {'early-installer' if early else 'inactive'} development BIOS: {output / 'IO.SYS'}", flush=True)
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--early", action="store_true", help="embed the early installer and poison old code after activation")
    parser.add_argument("--tail-body", action="store_true", help="link the fallback body after retained BIOS code")
    parser.add_argument("--dispatch", action="store_true", help="include complete high decoder and device tables")
    parser.add_argument("--characters", action="store_true", help="bind the complete high character service owner")
    parser.add_argument("--scan", action="store_true", help="capture activation-time ownership on QEMU debug port")
    parser.add_argument("--rebase", action="store_true", help="move and poison the old low DOS prefix")
    parser.add_argument("--compact", action="store_true", help="coalesce the first-HIMEM boot allocation after rebasing")
    parser.add_argument("--high-cds", action="store_true")
    parser.add_argument("--fail-cds-allocation", action="store_true")
    parser.add_argument("--cds-cache-case", choices=("first", "last", "past-end", "foreign"))
    parser.add_argument("--cds-cache-negative", action="store_true")
    args = parser.parse_args()
    build(args.output, early=args.early, tail_body=args.tail_body, dispatch=args.dispatch, characters=args.characters,
          scan=args.scan, rebase=args.rebase, compact=args.compact,
          high_cds=args.high_cds, fail_cds=args.fail_cds_allocation,
          cds_cache_case=args.cds_cache_case, cds_cache_negative=args.cds_cache_negative)
