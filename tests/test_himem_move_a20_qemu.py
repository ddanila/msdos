#!/usr/bin/env python3
"""Check A20 preservation across XMS and BIOS moves, including BIOS failures."""

import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

from test_compat_bpb_qemu import put, run

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--himem", type=Path, required=True)
    parser.add_argument("--boot-image", type=Path, default=ROOT / "out/floppy.img")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="himem-move-a20-", dir=ROOT / "out"))
    print(work, flush=True)
    report = {
        "himem_sha256": digest(args.himem),
        "boot_image_sha256": digest(args.boot_image),
        "cases": [],
    }
    for source, name in (
        ("himem_a20_drop_driver.asm", "A20DROP.SYS"),
        ("himem_move_a20_probe.asm", "A20PROBE.COM"),
    ):
        run(["nasm", "-f", "bin", ROOT / "tests" / source, "-o", work / name])
    # DOS LOW allows forcing both physical A20 states without invalidating DOS.
    for mode in ("LOW",):
        image = work / (mode + ".img")
        image.write_bytes(args.boot_image.read_bytes())
        for name in ("A20DROP.SYS", "A20PROBE.COM"):
            put(image, name, (work / name).read_bytes())
        put(image, "HIMEM.SYS", args.himem.read_bytes())
        put(
            image,
            "CONFIG.SYS",
            (
                "DEVICE=A:\\A20DROP.SYS\r\nDEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\nDOS="
                + mode
                + "\r\n"
            ).encode(),
        )
        put(image, "AUTOEXEC.BAT", b"@ECHO OFF\r\nA20PROBE.COM\r\n")
        log = work / (mode + ".log")
        with log.open("wb") as stream:
            result = subprocess.run(
                [
                    "qemu-system-i386",
                    "-m",
                    "16M",
                    "-display",
                    "none",
                    "-monitor",
                    "none",
                    "-serial",
                    "stdio",
                    "-no-reboot",
                    "-drive",
                    f"file={image},format=raw,if=floppy",
                    "-boot",
                    "a",
                    "-device",
                    "isa-debug-exit,iobase=0xf4,iosize=0x04",
                ],
                stdout=stream,
                stderr=subprocess.STDOUT,
                timeout=45,
                check=False,
            )
        data = log.read_bytes()
        passed = (
            result.returncode == 1
            and b"HIMEM_MOVE_A20_PASS" in data
            and b"HIMEM_MOVE_A20_FAIL" not in data
        )
        report["cases"].append(
            {
                "mode": mode,
                "passed": passed,
                "exit_status": result.returncode,
                "log_sha256": digest(log),
            }
        )
        (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    assert all(case["passed"] for case in report["cases"]), report["cases"]


if __name__ == "__main__":
    main()
