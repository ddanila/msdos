#!/usr/bin/env python3
"""Exercise an actual privileged instruction, retained dialog and safe Continue."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

from build_bios_low_image import ROOT, build
from capture_vc_memory_comparison import image_file
from screen_expect import QMPConnection, read_screen_text
from test_dos_char_retirement_qemu import install


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--fault", choices=("lidt", "cr2"), default="lidt")
    parser.add_argument("--ems-live", action="store_true", help="allocate an application EMS handle before faulting")
    parser.add_argument("--standalone", action="store_true",
                        help="use freshly built normal EMM without RAM/NOEMS upper owners")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="emm-error-runtime-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    disk = work / "boot.img"
    shutil.copyfile(args.image, disk)
    if args.standalone:
        assert image_file(disk, "::MSDOS.SYS") == (ROOT / "src/DOS/MSDOS.SYS").read_bytes()
        build(work / "bios")
        install(disk, "IO.SYS", (work / "bios/IO.SYS").read_bytes())
        install(disk, "DOS/EMM386.EXE", (ROOT / "src/MEMM/MEMM/EMM386.EXE").read_bytes())
        install(disk, "CONFIG.SYS", b"DEVICE=C:\\DOS\\HIMEM.SYS\r\nDOS=HIGH\r\n"
                b"DEVICE=C:\\DOS\\EMM386.EXE\r\nFILES=30\r\nBUFFERS=15\r\n")
    subprocess.run(["nasm", "-f", "bin", *(["-DFAULT_CR2"] if args.fault == "cr2" else []),
                    *(["-DLIVE_EMS"] if args.ems_live else []),
                    ROOT / "tests/emm_error_continue.asm",
                    "-o", work / "FAULT.COM"], check=True)
    install(disk, "FAULT.COM", (work / "FAULT.COM").read_bytes())
    install(disk, "AUTOEXEC.BAT", b"@ECHO OFF\r\nFAULT.COM\r\n")
    debug = work / "debug.log"
    with (work / "qemu.log").open("wb") as log:
        process = subprocess.Popen([
            "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
            "-display", "none", "-monitor", "none", "-serial", "none", "-boot", "c",
            "-no-reboot", "-drive", f"if=ide,format=raw,file={disk}",
            "-qmp", f"unix:{work / 'qmp'},server=on,wait=off", "-debugcon", f"file:{debug}",
            "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"], stdout=log, stderr=log)
        try:
            qmp = QMPConnection(str(work / "qmp"))
            deadline = time.monotonic() + 40
            screen = ""
            while time.monotonic() < deadline and process.poll() is None:
                screen = read_screen_text(qmp, str(work / "screen.bin"))
                if "EMM386 privileged error #" in screen and "Reboot (B)?" in screen:
                    break
                time.sleep(.2)
            (work / "screen.txt").write_text(screen)
            assert "EMM386 privileged error #" in screen and "Reboot (B)?" in screen, screen
            can_continue = args.standalone and not args.ems_live
            assert ("Continue (C)?" in screen) == can_continue, screen
            qmp.send_key("c")
            if can_continue:
                code = process.wait(timeout=15)
                assert code == 33 and b"ERROR_CONTINUE_PASS" in debug.read_bytes(), debug.read_bytes()
            else:
                time.sleep(2)
                assert process.poll() is None
                assert b"ERROR_CONTINUE_" not in debug.read_bytes()
                assert "Reboot (B)?" in read_screen_text(qmp, str(work / "screen.bin"))
                qmp.send_key("b")
                code = process.wait(timeout=15)
                assert code == 0, code  # -no-reboot exits only after the reset request
            (work / "result.json").write_text(json.dumps(dict(
                passed=True, standalone=args.standalone, fault=args.fault, ems_live=args.ems_live,
                exit_code=code, provider_sha256=hashlib.sha256(image_file(disk, "::DOS/EMM386.EXE")).hexdigest(),
                input_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest()), indent=2) + "\n")
            print("Privileged dialog/continuation: PASS", flush=True)
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)


if __name__ == "__main__":
    main()
