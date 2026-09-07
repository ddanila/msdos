#!/usr/bin/env python3
"""Compare installed low/high character services with deterministic IRQ hooks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from build_bios_low_image import ROOT, build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--omit-keyboard-restore", action="store_true", help="negative control: remove the high build's low INT 16h A20 restoration")
    args = parser.parse_args()
    subprocess.run(["make", "dos", "bios", str(ROOT / "src/DEV/HIMEM/HIMEM.SYS")], cwd=ROOT, check=True)
    work = Path(tempfile.mkdtemp(prefix="bios-character-requests-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    source_image = Path(os.environ.get("FLOPPY_IMAGE", ROOT / "out/floppy.img"))
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    traces, reports = {}, {}
    for name, characters in (("low", False), ("high", True)):
        directory = work / name
        report = build(directory, early=True, tail_body=True, dispatch=True, characters=characters)
        symbols = report["symbols"]
        names = ("CONHEADER", "AUXDEV2", "PRNDEV2", "TIMDEV", "ALTAH", "AUXBUF", "DAYCNT", "HAVECMOSCLOCK", "FHAVEK09",
                 "DSKTBL", "CONTBL", "AUXTBL", "PRNTBL", "TIMTBL")
        high = json.loads((directory / "high/bios-high.json").read_text())
        definitions = {symbol: symbols[symbol] for symbol in names}
        definitions.update(ACTIVE_OFFSET=symbols["BIOS_SERVICE_ACTIVE"], DISPATCH_SLOT=symbols["BIOS_HIGH_DISPATCH_ENTRY"],
                           DISPATCH_OFFSET=high["exports"]["BIOS_DISPATCH_START"], TABLES_OFFSET=high["exports"]["BIOS_DISPATCH_TABLES"],
                           EXPECTED_TARGET_SEGMENT=0xffff if characters else 0x70)
        (directory / "character-defs.inc").write_text("".join(f"{symbol} equ {value}\n" for symbol, value in definitions.items()))
        probe = directory / "CHARS.COM"
        subprocess.run(["nasm", "-f", "bin", f"-I{directory}/", ROOT / "tests/bios_character_requests.asm",
                        "-o", probe], check=True)
        image = directory / "boot.img"
        shutil.copyfile(source_image, image)
        config = "DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\nDOS=HIGH\r\n"
        (directory / "CONFIG.SYS").write_bytes(config.encode("ascii"))
        (directory / "AUTOEXEC.BAT").write_bytes(b"@ECHO OFF\r\nCHARS.COM\r\n")
        bios_image = directory / "IO.SYS"
        if characters and args.omit_keyboard_restore:
            data = bytearray(bios_image.read_bytes())
            gate = len(data) - (directory / "MSBIO.BIN").stat().st_size + symbols["BIOS_HMA_INT16"]
            if data[gate:gate+3] != b"\xcd\x16\xe8" or data[gate+5] != 0xcb:
                raise ValueError("INT 16h gate changed; review negative control")
            data[gate+2:gate+5] = b"\x90" * 3
            bios_image = directory / "IO-NORESTORE.SYS"
            bios_image.write_bytes(data)
        inputs = [(bios_image, "IO.SYS"), (ROOT / "src/DOS/MSDOS.SYS", "MSDOS.SYS"),
                  (ROOT / "src/DEV/HIMEM/HIMEM.SYS", "HIMEM.SYS"),
                  (ROOT / "src/CMD/COMMAND/COMMAND.COM", "COMMAND.COM"), (probe, "CHARS.COM"),
                  (directory / "CONFIG.SYS", "CONFIG.SYS"), (directory / "AUTOEXEC.BAT", "AUTOEXEC.BAT")]
        for source, destination in inputs:
            subprocess.run(["mcopy", "-o", "-i", image, source, f"::{destination}"], env=env, check=True)
        command = ["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
                   "-display", "none", "-monitor", "none", "-serial", "none", "-boot", "a", "-no-reboot",
                   "-drive", f"if=floppy,format=raw,file={image},cache=writethrough",
                   "-debugcon", f"file:{directory / 'trace.txt'}",
                   "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
        timed_out = False
        try:
            result = subprocess.run(command, capture_output=True, timeout=25)
            code, log = result.returncode, result.stdout + result.stderr
        except subprocess.TimeoutExpired as error:
            timed_out, code = True, None
            log = (error.stdout or b"") + (error.stderr or b"")
        (directory / "qemu.log").write_bytes(log)
        trace = (directory / "trace.txt").read_bytes()
        reports[name] = dict(exit_code=code, timed_out=timed_out, trace=trace.decode("ascii", errors="replace"),
                             omitted_keyboard_restore=characters and args.omit_keyboard_restore,
                             inputs={destination: hashlib.sha256(source.read_bytes()).hexdigest() for source, destination in inputs},
                             emulator_command=list(map(str, command)))
        (work / "results.json").write_text(json.dumps(reports, indent=2) + "\n")
        if code != 33 or not re.fullmatch(rb"(?:[0-9A-F]{26}\n){19}P", trace):
            raise RuntimeError(f"{name} character requests failed: {directory}, exit={code}, trace={trace!r}")
        records = [bytes.fromhex(line.decode()) for line in trace.splitlines()[:-1]]
        if [record[-1] for record in records] != [2,2,2,16,16,1,1,0,1,1,1,4,4,4,4,0,8,8,8]:
            raise RuntimeError(f"unexpected firmware activity: {directory}")
        reports[name]["passed"] = True
        traces[name] = trace
    if traces["low"] != traces["high"]:
        raise RuntimeError(f"character request transcripts differ: {work}")
    reports["comparison"] = dict(matched=True, requests=19,
                                  emulator=subprocess.check_output(["qemu-system-i386", "--version"], text=True).splitlines()[0])
    (work / "results.json").write_text(json.dumps(reports, indent=2) + "\n")
    print("PASS: 19 actual low/high device requests match; frames preserved; hooks disable A20")


if __name__ == "__main__":
    main()
