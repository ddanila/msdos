#!/usr/bin/env python3
"""Smoke-test the source-built DWED overlay on private DOS LOW/HIGH images.

Temporary adoption gate: uses the explicitly selected historical launcher until
its source-built replacement is ready. Requires a built parent out/floppy.img.
"""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--build", type=Path, default=ROOT / "dwed/out/build")
parser.add_argument("--launcher", type=Path, default=ROOT / "dwed/BIN/DWED.EXE")
args = parser.parse_args()
overlay = args.build.resolve() / "DWEDOVL.exe"
launcher = args.launcher.resolve()
for required in (overlay, launcher, ROOT / "out/floppy.img"):
    if not required.is_file():
        parser.error(f"missing input: {required}")
from screen_expect import QMPConnection, read_screen_text, send_keys
from test_compat_bpb_qemu import disk, put, run

WORK = Path(tempfile.mkdtemp(prefix="dwed-qemu-", dir=ROOT / "out"))
print(WORK, flush=True)
repo = ROOT / "dwed"
rows = []
cases = [
    ("edit-" + mode, mode, b"DWED_MARKER\r\nsecond line\r\n", True)
    for mode in ("low", "high")
]
for name, mode, original, edit in cases:
    d = WORK / name
    d.mkdir()
    floppy = d / "boot.img"
    shutil.copyfile(ROOT / "out/floppy.img", floppy)
    hdd, _, _ = disk(d, {})
    spec = f"{hdd}@@32256"
    run(["mmd", "-i", spec, "::DWED"])
    for file, dos_name in (
        (launcher, "DWED.EXE"),
        (overlay, "DWEDOVL.EXE"),
        (repo / "BIN/DWED.CFG", "DWED.CFG"),
    ):
        run(["mcopy", "-o", "-i", spec, file, "::DWED/" + dos_name])
    put(spec, "SAMPLE.TXT", original)
    asm = d / "exit.asm"
    asm.write_text("bits 16\norg 100h\nmov dx,0f4h\nmov ax,10h\nout dx,ax\nhlt\n")
    run(["nasm", "-f", "bin", asm, "-o", d / "EXIT.COM"])
    put(floppy, "QEXIT.COM", (d / "EXIT.COM").read_bytes())
    config = b"FILES=40\r\nBUFFERS=15\r\nDOS=LOW\r\n"
    if mode == "high":
        config = b"DEVICE=A:\\HIMEM.SYS\r\nDEVICE=A:\\EMM386.EXE NOEMS\r\nDOS=HIGH,UMB\r\nFILES=40\r\nBUFFERS=15\r\n"
    put(floppy, "CONFIG.SYS", config)
    put(
        floppy,
        "AUTOEXEC.BAT",
        b"@ECHO OFF\r\nC:\r\nCD \\DWED\r\nDWED.EXE C:\\SAMPLE.TXT\r\nA:\\QEXIT.COM\r\n",
    )
    socket = d / "qmp"
    argv = [
        "qemu-system-i386",
        "-machine",
        "pc",
        "-cpu",
        "486",
        "-m",
        "16",
        "-accel",
        "tcg,thread=single",
        "-d",
        "nochain",
        "-display",
        "none",
        "-monitor",
        "none",
        "-serial",
        f"file:{d}/serial.log",
        "-qmp",
        f"unix:{socket},server=on,wait=off",
        "-no-reboot",
        "-nic",
        "none",
        "-boot",
        "a",
        "-drive",
        f"if=floppy,format=raw,file={floppy}",
        "-drive",
        f"if=ide,format=raw,file={hdd}",
        "-device",
        "isa-debug-exit,iobase=0xf4,iosize=0x04",
    ]
    (d / "command.json").write_text(json.dumps(argv, indent=2))
    process = subprocess.Popen(
        argv, stdout=subprocess.DEVNULL, stderr=(d / "qemu.log").open("wb")
    )
    row = {"case": name, "mode": mode, "original_hex": original.hex()}
    try:
        q = QMPConnection(str(socket))
        end = time.monotonic() + 30
        screen = ""
        while time.monotonic() < end and process.poll() is None:
            screen = read_screen_text(q, str(d / "vram.bin"))
            if "DWED_MARKER" in screen:
                break
            time.sleep(0.2)
        (d / "opened.txt").write_text(screen)
        assert "DWED_MARKER" in screen, screen
        q.human_cmd(f'screendump "{d}/opened.ppm"')
        if edit:
            send_keys(q, "home+z")
            time.sleep(0.25)
        send_keys(q, "f2")
        time.sleep(0.5)
        (d / "saved.txt").write_text(read_screen_text(q, str(d / "vram.bin")))
        send_keys(q, "esc")
        process.wait(timeout=15)
        assert process.returncode == 33, process.returncode
        actual = run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout
        backup = run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout
        row.update(
            completed=True,
            actual_hex=actual.hex(),
            backup_matches_original=backup == original,
            exact_match=actual == (b"z" + original if edit else original),
        )
        (d / "original.bin").write_bytes(original)
        (d / "saved.bin").write_bytes(actual)
    except Exception as error:  # noqa: BLE001 -- record diagnostics, then fail the suite below
        row.update(completed=False, error=str(error))
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
    rows.append(row)
    (WORK / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
    print(row, flush=True)
print("Finished", flush=True)

assert all(
    r.get("completed") and r.get("exact_match") and r.get("backup_matches_original")
    for r in rows
), rows
