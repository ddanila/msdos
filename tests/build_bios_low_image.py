#!/usr/bin/env python3
"""Link an inactive, relocation-capable BIOS without replacing normal IO.SYS."""
from pathlib import Path
import argparse
import hashlib
import json
import runpy
import re
import subprocess

from build_bios_high_payload import ROOT, run
from report_dos_bios_residency import parse_map


def build(output, *, early=False, reservation_limit=0xfff0, tail_body=False):
    if not 0 <= reservation_limit <= 0xfff0:
        raise ValueError("invalid development reservation ceiling")
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    embedded = None
    if early:
        from build_bios_high_payload import build as build_high
        from build_bios_activation_fixture import write_fixture
        seed = build(output, tail_body=tail_body)
        high = build_high(output / "high", output)
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
    if tail_body:
        options += " -DBIOS_SERVICE_TAIL_BODY=1"
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
                "reservation_limit": reservation_limit, "tail_body": tail_body}
    if early:
        # Init-segment growth must not invalidate any embedded low operands.
        for name, value in seed["symbols"].items():
            if name in high["low_bindings"] or name.startswith("BIOS_") or name == "DSKTBL":
                if symbols[name] != value:
                    raise ValueError(f"early link moved embedded low binding: {name}")
        final_high = build_high(output / "high", output)
        if (output / "high/bios-high.bin").read_bytes() != embedded:
            raise ValueError("early link changed the embedded high payload")
        manifest["embedded_payload_bytes"] = final_high["bytes"]
    (output / "low.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"Linked {'early-installer' if early else 'inactive'} development BIOS: {output / 'IO.SYS'}", flush=True)
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--early", action="store_true", help="embed the early installer and poison old code after activation")
    parser.add_argument("--tail-body", action="store_true", help="link the fallback body after retained BIOS code")
    args = parser.parse_args()
    build(args.output, early=args.early, tail_body=args.tail_body)
