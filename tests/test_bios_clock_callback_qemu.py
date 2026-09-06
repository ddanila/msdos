#!/usr/bin/env python3
"""Qualify the installed clock near hook after whole-body retirement."""
import hashlib
import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

from build_bios_low_image import ROOT, build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack-headers", action="store_true", help="qualify the packed low device-header layout")
    parser.add_argument("--retire-media", action="store_true", help="qualify the retired media/BPB layout")
    args = parser.parse_args()
    subprocess.run(["make", "dos", "bios", "cmd_command", str(ROOT / "src/DEV/HIMEM/HIMEM.SYS")],
                   cwd=ROOT, check=True)
    work = Path(tempfile.mkdtemp(prefix="bios-clock-callback-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    source = Path(os.environ.get("FLOPPY_IMAGE", ROOT / "floppy.img"))
    samples = [struct.pack("<I", ticks * 59659 // 327680)
               for ticks in (0, 360000, 4529678, 8639999)]
    reports = {}
    for name, active, compact, omit in (("fallback", False, False, False),
                                        ("high-poisoned", True, False, False),
                                        ("high-compacted", True, True, False),
                                        ("missing-restore", True, False, True)):
        directory = work / name
        low = build(directory, early=True, tail_body=True, dispatch=True,
                    characters=True, retire_characters=True, rebase=compact,
                    compact=compact, pack_headers=args.pack_headers, retire_media=args.retire_media,
                    reservation_limit=0xfff0 if active else 0x10)
        symbols = low["symbols"]
        binary = (directory / "MSBIO.BIN").read_bytes()
        gate = symbols["TIME_TO_TICKS"]
        restore = symbols["BIOS_HMA_ROM_RESTORE"]
        calls = [i for i in range(gate, gate + 30) if binary[i] == 0xe8
                 and (i + 3 + int.from_bytes(binary[i+1:i+3], "little", signed=True)) & 0xffff == restore]
        if len(calls) != 1:
            raise ValueError("clock gate must have one direct A20 restore call")
        definitions = dict(ACTIVE=symbols["BIOS_SERVICE_ACTIVE"], CALLBACK=symbols["TIMETOTICKS"],
                           EXPECT_ACTIVE=int(active), OMIT_RESTORE=int(omit), RESTORE_CALL=calls[0],
                           EXPECT_POISON=int(active and not compact), OLD_START=symbols["CON$READ"],
                           OLD_SIZE=symbols["BIOS_SERVICE_END"]-symbols["CON$READ"])
        (directory / "clock-defs.inc").write_text("".join(f"{k} equ {v}\n" for k, v in definitions.items()))
        probe = directory / "CLOCK.COM"
        subprocess.run(["nasm", "-f", "bin", f"-I{directory}/", ROOT / "tests/bios_clock_callback.asm",
                        "-o", probe], check=True)
        image = directory / "boot.img"
        shutil.copyfile(source, image)
        for filename, data in (("CONFIG.SYS", "DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\nDOS=HIGH\r\n"),
                               ("AUTOEXEC.BAT", "@ECHO OFF\r\nCLOCK.COM\r\n")):
            (directory / filename).write_text(data)
        for path, target in ((directory / "IO.SYS", "IO.SYS"),
                             (ROOT / "src/DOS/MSDOS.SYS", "MSDOS.SYS"),
                             (ROOT / "src/CMD/COMMAND/COMMAND.COM", "COMMAND.COM"),
                             (ROOT / "src/DEV/HIMEM/HIMEM.SYS", "HIMEM.SYS"),
                             (probe, "CLOCK.COM"), (directory / "CONFIG.SYS", "CONFIG.SYS"),
                             (directory / "AUTOEXEC.BAT", "AUTOEXEC.BAT")):
            subprocess.run(["mcopy", "-o", "-i", image, path, "::" + target], env=env, check=True)
        debug = directory / "debug.bin"
        command = ["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
                   "-display", "none", "-monitor", "none", "-serial", "none", "-no-reboot",
                   "-drive", f"if=floppy,format=raw,file={image}", "-boot", "a",
                   "-debugcon", f"file:{debug}", "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
        try:
            result = subprocess.run(command, timeout=20, capture_output=True)
            code, output = result.returncode, result.stdout + result.stderr
        except subprocess.TimeoutExpired as error:
            code = None
            output = (error.stdout or b"") + (error.stderr or b"")
        (directory / "qemu.log").write_bytes(output)
        trace = debug.read_bytes() if debug.exists() else b""
        expected = b"B" + b"".join((b"O" if active else b"") + sample for sample in samples) + b"P"
        passed = code == 33 and trace == expected
        reports[name] = dict(exit_code=code, trace=trace.hex(), successful_callback=passed,
                             expected_trace=expected.hex(), negative_control=omit,
                             image_sha256=hashlib.sha256(image.read_bytes()).hexdigest(), command=command,
                             inputs={str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                                     for path in (Path(__file__), ROOT / "tests/bios_clock_callback.asm",
                                                  directory / "low.json", probe)},
                             emulator=subprocess.check_output(["qemu-system-i386", "--version"], text=True).splitlines()[0])
        (work / "results.json").write_text(json.dumps(reports, indent=2) + "\n")
        if passed == omit or (omit and trace != b"BO"):
            raise RuntimeError(f"unexpected callback result: {name}: {code}, {trace.hex()}")
        print(f"PASS {name}: {'negative control rejected' if omit else 'four exact results and intact frames'}", flush=True)


if __name__ == "__main__":
    main()
