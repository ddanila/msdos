#!/usr/bin/env python3
"""Measure editor startup with a test TSR limiting contiguous DOS memory."""

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
    parser.add_argument("--mode", choices=("low", "high"), default="low")
    parser.add_argument(
        "--kib",
        type=int,
        nargs="+",
        default=[248, 252, 260, 268, 280, 304, 308, 336, 340, 344, 348, 352],
    )
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="dwed-startup-", dir=ROOT / "out"))
    print(work, flush=True)
    report = {
        "mode": args.mode,
        "build": json.loads((args.build / "build.json").read_text()),
        "boot_image_sha256": hashlib.sha256(
            (ROOT / "out/floppy.img").read_bytes()
        ).hexdigest(),
        "core_sha256": {
            n: hashlib.sha256((args.core / n).read_bytes()).hexdigest()
            for n in ("HIMEM.SYS", "EMM386.EXE")
        },
        "cases": [],
    }
    for kib in args.kib:
        assert 64 <= kib <= 576, kib
        directory = work / str(kib)
        directory.mkdir()
        floppy = directory / "boot.img"
        shutil.copyfile(ROOT / "out/floppy.img", floppy)
        for name in ("HIMEM.SYS", "EMM386.EXE"):
            put(floppy, name, (args.core / name).read_bytes())
        hdd, _, _ = disk(directory, {})
        spec = f"{hdd}@@32256"
        run(["mmd", "-i", spec, "::DWED"])
        for source, target in [
            ("DWED.COM", "DWED.COM"),
            ("DWEDOVL.exe", "DWEDOVL.EXE"),
            ("DWED.CFG", "DWED.CFG"),
        ]:
            put(spec, "DWED/" + target, (args.build / source).read_bytes())
        original = b"DWED_MARKER\r\nsecond line\r\n"
        backup = b"PREVIOUS BACKUP\r\n"
        put(spec, "SAMPLE.TXT", original)
        put(spec, "SAMPLE.BAK", backup)
        run(
            [
                "nasm",
                "-f",
                "bin",
                f"-DLIMIT_KIB={kib}",
                ROOT / "tests/dwed_memory_cap.asm",
                "-o",
                directory / "CAP.COM",
            ]
        )
        put(floppy, "CAP.COM", (directory / "CAP.COM").read_bytes())
        put(floppy, "EXIT.COM", bytes.fromhex("b81000e7f4f4ebfd"))
        config = "FILES=40\r\nBUFFERS=15\r\nDOS=LOW\r\n"
        if args.mode == "high":
            config = "DEVICE=A:\\HIMEM.SYS\r\nDEVICE=A:\\EMM386.EXE NOEMS\r\nDOS=HIGH,UMB\r\nFILES=40\r\nBUFFERS=15\r\n"
        put(floppy, "CONFIG.SYS", config.encode())
        put(
            floppy,
            "AUTOEXEC.BAT",
            (
                b"@ECHO OFF\r\nA:\\CAP.COM\r\nIF ERRORLEVEL 1 GOTO CAPFAIL\r\n"
                b"C:\r\nCD \\DWED\r\nDWED.COM C:\\SAMPLE.TXT >C:\\START.LOG\r\n"
                b"IF ERRORLEVEL 8 ECHO INIT8>C:\\STATUS.TXT\r\nGOTO DONE\r\n"
                b":CAPFAIL\r\nECHO FAIL>C:\\CAPFAIL.TXT\r\n:DONE\r\nA:\\EXIT.COM\r\n"
            ),
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
        row = {"free_block_kib": kib}
        edited = False
        with (directory / "qemu.log").open("wb") as stderr:
            process = subprocess.Popen(
                command, stdout=subprocess.DEVNULL, stderr=stderr
            )
            try:
                q = QMPConnection(str(socket))
                deadline = time.monotonic() + 45
                while process.poll() is None and time.monotonic() < deadline:
                    try:
                        screen = read_screen_text(q, str(directory / "vram.bin"))
                    except (OSError, EOFError):
                        process.wait(timeout=5)
                        break
                    (directory / "screen.txt").write_text(screen)
                    if not edited and "DWED_MARKER" in screen:
                        send_keys(q, "home+z+f2")
                        time.sleep(0.5)
                        send_keys(q, "esc")
                        edited = True
                    time.sleep(0.2)
                process.wait(timeout=5)
                assert process.returncode == 33, process.returncode
                listing = run(["mdir", "-b", "-i", spec, "::"]).stdout.upper()
                assert b"CAPFAIL" not in listing, listing
                log = (
                    run(["mtype", "-i", spec, "::START.LOG"])
                    .stdout.decode("ascii", errors="replace")
                    .strip()
                )
                actual = run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout
                actual_backup = run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout
                if edited:
                    assert actual == b"z" + original and actual_backup == original
                    row["outcome"] = "edited"
                else:
                    assert actual == original and actual_backup == backup
                    assert log.startswith(
                        (
                            "EDIT: Not enough memory for ",
                            "DWED: cannot execute DWEDOVL.EXE.",
                        )
                    ), log
                    row["outcome"] = log
                    if log.startswith("EDIT:"):
                        assert (
                            run(["mtype", "-i", spec, "::STATUS.TXT"]).stdout.strip()
                            == b"INIT8"
                        )
                row["completed"] = True
            except Exception as error:  # noqa: BLE001 -- record each guest failure, then fail the matrix
                row.update(completed=False, error=str(error))
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
        report["cases"].append(row)
        (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        print(row, flush=True)
    assert all(row["completed"] for row in report["cases"]), report["cases"]
    assert any(row.get("outcome") == "edited" for row in report["cases"]), (
        "No successful startup control"
    )
    assert any(row.get("outcome", "").startswith("EDIT:") for row in report["cases"]), (
        "No initialization-refusal control"
    )


if __name__ == "__main__":
    main()
