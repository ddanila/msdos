#!/usr/bin/env python3
"""Check the complete console workspace, its overlap and persistent read cursor."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

from build_bios_low_image import ROOT
from capture_vc_memory_comparison import image_file
from report_dos_bios_residency import parse_map
from screen_expect import QMPConnection, read_screen_text, send_keys
from test_dos_char_retirement_qemu import install


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--low-bios", type=Path, help="also check standalone LOW with a matched inactive BIOS")
    parser.add_argument("--low-only", action="store_true")
    parser.add_argument("--kernel-map", type=Path,
                        help="matched map/SYS pair; force the idle clock-refresh path before reads")
    args = parser.parse_args()
    if args.low_only and not args.low_bios:
        parser.error("--low-only requires --low-bios")
    work = Path(tempfile.mkdtemp(prefix="dos-console-runtime-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    defines = []
    if args.kernel_map:
        assert args.kernel_map.with_suffix(".SYS").read_bytes() == image_file(args.image, "::MSDOS.SYS")
        _, symbols = parse_map(args.kernel_map)
        defines.append(f"-DDATE_FLAG_OFFSET={symbols['DATE_FLAG']}")
    subprocess.run(["nasm", "-f", "bin", *defines, ROOT / "tests/dos_console_workspace.asm",
                    "-o", work / "CONTEST.COM"], check=True)
    for mode in (("LOW",) if args.low_only else (("HIGH", "LOW") if args.low_bios else ("HIGH",))):
        disk = work / f"{mode}.img"
        shutil.copyfile(args.image, disk)
        if mode == "LOW":
            install(disk, "IO.SYS", args.low_bios.read_bytes())
            install(disk, "CONFIG.SYS", b"DOS=LOW\r\nFILES=30\r\nBUFFERS=15\r\n")
        install(disk, "CONTEST.COM", (work / "CONTEST.COM").read_bytes())
        install(disk, "LINE.TXT", b"x" * 254 + b"\r\n")
        install(disk, "AUTOEXEC.BAT", b"@ECHO OFF\r\nCONTEST.COM\r\n")
        debug = work / f"{mode}.debug"
        socket = work / f"{mode}.qmp"
        with (work / f"{mode}.log").open("wb") as log:
            process = subprocess.Popen([
                "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
                "-display", "none", "-monitor", "none", "-serial", "none", "-boot", "c",
                "-no-reboot", "-drive", f"if=ide,format=raw,file={disk}",
                "-qmp", f"unix:{socket},server=on,wait=off", "-debugcon", f"file:{debug}",
                "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"], stdout=log, stderr=log)
            qmp = None
            try:
                qmp = QMPConnection(str(socket))
                for marker, keys in (("CONSOLE_CHUNKS_READY", "a+b+c+ret"),
                                     ("CONSOLE_EDIT_READY", "x+y+backspace+z+ret")):
                    deadline = time.monotonic() + 40
                    screen = ""
                    while process.poll() is None and time.monotonic() < deadline:
                        screen = read_screen_text(qmp, str(work / f"{mode}.screen"))
                        if marker in screen:
                            break
                        time.sleep(.2)
                    (work / f"{mode}-{marker}.txt").write_text(screen)
                    assert marker in screen, (screen, debug.read_bytes())
                    send_keys(qmp, keys)
                assert process.wait(timeout=20) == 33, debug.read_bytes()
                assert debug.read_bytes().endswith(b"CONSOLE_WORKSPACE_PASS")
                print(f"Console workspace {mode}: PASS", flush=True)
            finally:
                if qmp is not None:
                    qmp.close()
                if process.poll() is None:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    main()
