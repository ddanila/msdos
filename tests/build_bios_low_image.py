#!/usr/bin/env python3
"""Link an inactive, relocation-capable BIOS without replacing normal IO.SYS."""
from pathlib import Path
import argparse
import hashlib
import json
import runpy
import subprocess

from build_bios_high_payload import ROOT, run
from report_dos_bios_residency import parse_map


def build(output):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    bios = ROOT / "src/BIOS"
    changed = ("MSBIO1", "MSDISK", "MSBIO2")
    options = "-I. -I../INC " + " ".join(f"-DBIOS_SERVICE_{name}=1" for name in
        ("BINDINGS", "LOW_CALLS", "DEVICE_ENTRIES", "INTERRUPT_ENTRIES", "RESULT_HELPERS"))
    for name in changed:
        run([ROOT / "bin/jwasm-masm", options,
             f"{name}.ASM,{output / (name + '.OBJ')};"], bios)
    names = ("MSBIO1", "MSCON", "MSAUX", "MSLPT", "MSCLOCK", "MSDISK", "MSBIO2",
             "MSHARD", "MSINIT", "SYSINIT1", "SYSCONF", "SYSINIT2", "SYSIMES")
    objects = [(output if name in changed else bios) / (name + ".OBJ") for name in names]
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
                "high_slot_words": sorted(slot_words)}
    (output / "low.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"Linked inactive development BIOS: {output / 'IO.SYS'}", flush=True)
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    build(parser.parse_args().output)
