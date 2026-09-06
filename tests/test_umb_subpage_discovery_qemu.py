#!/usr/bin/env python3
"""Exercise development fine discovery without installing sub-page mappings."""

import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(command, **kwargs):
    return subprocess.run([str(x) for x in command], check=True, **kwargs)


def build(work, enabled, extra_flags="", *, high_tables=False):
    for name in ("MEMM", "EMM"):
        source, dest = ROOT / "src/MEMM" / name, work / name
        dest.mkdir(parents=True)
        for path in source.iterdir():
            if path.suffix.upper() in (".OBJ", ".LIB", ".LNK"):
                shutil.copyfile(path, dest / path.name)
    flags = "-Mx -t -DI386 -DNoBugMode -DNOHIMEM -I. -I..\\EMM"
    if enabled:
        flags += " -DUMB_SUBPAGE_DISCOVERY"
    flags += " " + extra_flags
    if high_tables:
        flags += " -DEMM_HIGH_TABLES"
    with (work / "build.log").open("w") as log:
        modules = ("INIT", "PPAGE")
        if high_tables:
            modules += ("EMMINIT", "INITTAB", "SHIPHI", "TABDEF")
        for module in modules:
            run([ROOT / "bin/jwasm-masm", flags,
                 f"{module}.ASM,{work / 'MEMM' / (module + '.OBJ')};"],
                cwd=ROOT / "src/MEMM/MEMM", stdout=log, stderr=subprocess.STDOUT)
        if high_tables:
            run([ROOT / "bin/jwasm-masm", flags.replace("-I..\\EMM", "-I..\\MEMM"),
                 f"EMMSUP.ASM,{work / 'EMM/EMMSUP.OBJ'};"],
                cwd=ROOT / "src/MEMM/EMM", stdout=log, stderr=subprocess.STDOUT)
        run([ROOT / "bin/wlink", "/NOI /PACKDATA:1 @EMM386.LNK"],
            cwd=work / "MEMM", stdout=log, stderr=subprocess.STDOUT)
    return work / "MEMM/EMM386.EXE"


def main():
    work = Path(tempfile.mkdtemp(prefix="umb-fine-discovery-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    original = ROOT / "src/MEMM/MEMM/EMM386.EXE"
    baseline = build(work / "normal", False)
    assert baseline.read_bytes() == original.read_bytes(), "normal binary changed"
    candidate = build(work / "fine", True, os.environ.get("UMB_SUBPAGE_FLAGS", ""))
    print(f"Unchanged normal SHA256: {hashlib.sha256(baseline.read_bytes()).hexdigest()}", flush=True)
    exit_com = work / "QEXIT.COM"
    run(["nasm", "-f", "bin", ROOT / "tests/qemu_exit.asm", "-o", exit_com])
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    cases = [
        ("base", "RAM M5", {10: 8, 11: 15, 12: 0, 16: 15}),
        ("exclude", "RAM M5 X=CB00-CBFF", {10: 0, 11: 15}),
        ("ix", "RAM M5 I=CB00-CBFF X=CB00-CBFF", {10: 0}),
        ("xi", "RAM M5 X=CB00-CBFF I=CB00-CBFF", {10: 0}),
        ("frame", "RAM M4", {10: 8, 11: 0, 14: 0, 15: 15}),
        ("noems", "NOEMS", {10: 8, 11: 15, 12: 15, 15: 15}),
        ("requested", "RAM M5 P4=CC00", {10: 8, 11: 0}),
    ]
    for name, options, expected in cases:
        image = work / f"{name}.img"
        shutil.copyfile(ROOT / "out/floppy.img", image)
        for source, dest in ((candidate, "::EMM386.EXE"), (exit_com, "::QEXIT.COM")):
            run(["mcopy", "-o", "-i", image, source, dest], env=env)
        files = {
            "CONFIG.SYS": f"DEVICE=HIMEM.SYS /TESTMEM:OFF\r\nDEVICE=EMM386.EXE {options}\r\nDOS=HIGH,UMB\r\n",
            "AUTOEXEC.BAT": "@ECHO OFF\r\nCTTY AUX\r\nECHO UMB_FINE_BOOT_PASS\r\nQEXIT.COM\r\n",
        }
        for filename, content in files.items():
            run(["mcopy", "-o", "-i", image, "-", "::" + filename],
                input=content.encode(), env=env)
        debug = work / f"{name}-debug.log"
        result = subprocess.run([
            "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
            "-display", "none", "-monitor", "none", "-serial", "stdio",
            "-drive", f"if=floppy,index=0,format=raw,file={image},cache=writethrough",
            "-boot", "a", "-no-reboot", "-debugcon", f"file:{debug}",
            "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        (work / f"{name}-serial.log").write_bytes(result.stdout)
        assert result.returncode == 33, (name, result.returncode, result.stdout)
        assert b"UMB_FINE_BOOT_PASS" in result.stdout, (name, result.stdout)
        assert b"Error in CONFIG" not in result.stdout, (name, result.stdout)
        matches = re.findall(rb"UMB_FINE=([0-9A-F]{20})\n", debug.read_bytes())
        assert len(matches) == 1, (name, debug.read_bytes())
        masks = [int(chr(x), 16) for x in matches[0]]
        assert masks[:8] == [0] * 8, (name, masks)
        assert masks[8:10] == [0, 0], (name, "ROM slices", masks)
        assert masks[18:] == [0, 0], (name, "firmware RAM", masks)
        for index, value in expected.items():
            assert masks[index] == value, (name, index, masks, value)
        print(f"PASS {name}: {matches[0].decode()}", flush=True)


if __name__ == "__main__":
    main()
