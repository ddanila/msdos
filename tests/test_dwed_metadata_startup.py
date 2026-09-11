#!/usr/bin/env python3
"""Reject damaged configuration before opening documents through the real launcher."""

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from screen_expect import QMPConnection, read_screen_text, send_keys
from test_compat_bpb_qemu import ROOT, disk, put, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--boot-image", type=Path, default=ROOT / "out/floppy.img")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="dwed-metadata-startup-", dir=ROOT / "out"))
    print(work, flush=True)
    report = {
        "build": json.loads((args.build / "build.json").read_text()),
        "boot_image_sha256": hashlib.sha256(args.boot_image.read_bytes()).hexdigest(),
        "core_sha256": {
            n: hashlib.sha256((args.core / n).read_bytes()).hexdigest()
            for n in ("HIMEM.SYS", "EMM386.EXE")
        },
        "cases": [],
    }
    for mode in ("low", "high"):
        for kind, bad in (
            ("control", b"tab_size=4\r\nbad\0record\r\n"),
            ("long", b"tab_size=4\r\n" + b"x" * 256 + b"\r\n"),
        ):
            directory = work / (kind + "-" + mode)
            directory.mkdir()
            floppy = directory / "boot.img"
            shutil.copyfile(args.boot_image, floppy)
            for name in ("HIMEM.SYS", "EMM386.EXE"):
                put(floppy, name, (args.core / name).read_bytes())
            hdd, _, _ = disk(directory, {})
            spec = f"{hdd}@@32256"
            run(["mmd", "-i", spec, "::DWED"])
            for source, target in (
                ("DWED.COM", "DWED.COM"),
                ("DWEDOVL.exe", "DWEDOVL.EXE"),
            ):
                put(spec, "DWED/" + target, (args.build / source).read_bytes())
            put(spec, "DWED/DWED.CFG", bad)
            original = b"DO NOT MODIFY\r\n"
            put(spec, "SAMPLE.TXT", original)
            put(floppy, "EXIT.COM", bytes.fromhex("b81000e7f4f4ebfd"))
            config = b"FILES=40\r\nBUFFERS=15\r\nDOS=LOW\r\n"
            if mode == "high":
                config = b"DEVICE=A:\\HIMEM.SYS\r\nDEVICE=A:\\EMM386.EXE NOEMS\r\nDOS=HIGH,UMB\r\nFILES=40\r\nBUFFERS=15\r\n"
            put(floppy, "CONFIG.SYS", config)
            put(
                floppy,
                "AUTOEXEC.BAT",
                b"@ECHO OFF\r\nC:\r\nCD \\DWED\r\nDWED.COM C:\\SAMPLE.TXT\r\nIF ERRORLEVEL 1 ECHO REFUSED>C:\\STATUS.TXT\r\nPAUSE\r\nA:\\EXIT.COM\r\n",
            )
            socket = directory / "qmp"
            command = [
                "qemu-system-i386",
                "-machine",
                "pc",
                "-cpu",
                "486",
                "-m",
                "16",
                "-accel",
                "tcg,thread=single",
                "-display",
                "none",
                "-monitor",
                "none",
                "-serial",
                "none",
                "-no-reboot",
                "-nic",
                "none",
                "-boot",
                "a",
                "-qmp",
                f"unix:{socket},server=on,wait=off",
                "-drive",
                f"if=floppy,format=raw,file={floppy}",
                "-drive",
                f"if=ide,format=raw,file={hdd}",
                "-device",
                "isa-debug-exit,iobase=0xf4,iosize=0x04",
            ]
            (directory / "command.json").write_text(json.dumps(command, indent=2))
            with (directory / "qemu.log").open("wb") as stderr:
                process = subprocess.Popen(
                    command, stdout=subprocess.DEVNULL, stderr=stderr
                )
                try:
                    q = QMPConnection(str(socket))
                    deadline = time.monotonic() + 30
                    screen = ""
                    while time.monotonic() < deadline and process.poll() is None:
                        screen = read_screen_text(q, str(directory / "vram.bin"))
                        if "Cannot read configuration" in screen and "Press" in screen:
                            break
                        time.sleep(0.2)
                    (directory / "refusal.txt").write_text(screen)
                    assert "Cannot read configuration" in screen, screen
                    assert "Invalid configuration or resume record" in screen, screen
                    assert "DO NOT MODIFY" not in screen, screen
                    send_keys(q, "ret")
                    process.wait(timeout=10)
                    assert (
                        run(["mtype", "-i", spec, "::STATUS.TXT"]).stdout.strip()
                        == b"REFUSED"
                    )
                    assert run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout == original
                    assert run(["mtype", "-i", spec, "::DWED/DWED.CFG"]).stdout == bad
                    report["cases"].append({"mode": mode, "kind": kind, "passed": True})
                    print(report["cases"][-1], flush=True)
                finally:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=5)
            (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
