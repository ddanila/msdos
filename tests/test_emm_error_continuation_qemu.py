#!/usr/bin/env python3
"""Exercise actual privileged/exception entries, retained dialogs and safe Continue."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

from build_bios_low_image import ROOT, build
from capture_vc_memory_comparison import image_file
from screen_expect import QMPConnection, read_screen_text
from test_dos_char_retirement_qemu import install
from report_emm386_residency import parse_map


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--fault", choices=("lidt", "cr2", "loadall", "loadall-exception"), default="lidt")
    parser.add_argument("--ems-live", action="store_true", help="allocate an application EMS handle before faulting")
    parser.add_argument("--provider-map", type=Path,
                        help="map and sibling EXE matching the composed exception-test provider")
    parser.add_argument("--standalone", action="store_true",
                        help="use freshly built normal EMM without RAM/NOEMS upper owners")
    args = parser.parse_args()
    if args.fault == "loadall-exception" and not args.standalone and not args.provider_map:
        parser.error("composed exception tests require --provider-map")
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
                    *(["-DFAULT_LOADALL"] if args.fault.startswith("loadall") else []),
                    *(["-DFAULT_EXCEPTION"] if args.fault == "loadall-exception" else []),
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
            exception = args.fault == "loadall-exception"
            heading = "EMM386 exception #" if exception else "EMM386 privileged error #"
            prompt = "Enter to reboot" if exception else "Reboot (B)?"
            deadline = time.monotonic() + 40
            screen = ""
            while time.monotonic() < deadline and process.poll() is None:
                screen = read_screen_text(qmp, str(work / "screen.bin"))
                if heading in screen and prompt in screen:
                    break
                time.sleep(.2)
            (work / "screen.txt").write_text(screen)
            assert heading in screen and prompt in screen, screen
            fault_location = None
            if exception:
                provider_map = ROOT / "src/MEMM/MEMM/EMM386.MAP" if args.standalone else args.provider_map
                provider = image_file(disk, "::DOS/EMM386.EXE")
                assert provider == provider_map.with_suffix(".EXE").read_bytes()
                segments, symbols = parse_map(provider_map)
                text = next(segment for segment in segments if segment.name == "_TEXT")
                entry = next(symbol.offset for symbol in symbols if symbol.name == "EM386ll")
                match = re.search(r"exception #06 @0038:([0-9A-F]{8}) Code 0000", screen)
                assert match, screen  # NOHIMEM's protected code selector, not a guest CS
                ip = int(match[1], 16)
                assert entry <= ip < text.size
                at = int.from_bytes(provider[8:10], "little") * 16 + text.paragraph * 16 + ip
                assert provider[at-3:at+2] == bytes.fromhex("83e7fc0f07"), "wrong protected fault location"
                fault_location = dict(selector=0x38, ip=ip, opcode="0f07")
            can_continue = args.standalone and not args.ems_live and not exception
            assert ("Continue (C)?" in screen) == can_continue, screen
            qmp.send_key("c")
            if can_continue:
                code = process.wait(timeout=15)
                assert code == 33 and b"ERROR_CONTINUE_PASS" in debug.read_bytes(), debug.read_bytes()
            else:
                time.sleep(2)
                assert process.poll() is None
                assert b"ERROR_CONTINUE_" not in debug.read_bytes()
                assert prompt in read_screen_text(qmp, str(work / "screen.bin"))
                qmp.send_key("ret" if exception else "b")
                code = process.wait(timeout=15)
                assert code == 0, code  # -no-reboot exits only after the reset request
            (work / "result.json").write_text(json.dumps(dict(
                passed=True, standalone=args.standalone, fault=args.fault, ems_live=args.ems_live,
                fault_location=fault_location,
                exit_code=code, provider_sha256=hashlib.sha256(image_file(disk, "::DOS/EMM386.EXE")).hexdigest(),
                input_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest()), indent=2) + "\n")
            print("Error dialog/continuation: PASS", flush=True)
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)


if __name__ == "__main__":
    main()
