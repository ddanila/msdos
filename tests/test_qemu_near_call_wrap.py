#!/usr/bin/env python3
"""Diagnose the QEMU TCG 16-bit near-call chaining bug and verify -d nochain."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from capture_dos_app_smoke import ROOT, install, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--floppy", type=Path, default=ROOT / "out/floppy.img")
    parser.add_argument("--require-default", action="store_true",
                        help="also require the default chaining path to work")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="qemu-near-call-wrap-", dir=ROOT / "out"))
    print(f"Evidence: {work}")
    probe = work / "WRAP.COM"
    run(["nasm", "-f", "bin", ROOT / "tests/qemu_near_call_wrap_probe.asm", "-o", probe])
    results = {}
    for mode in ("default", "nochain"):
        image = work / (mode + ".img")
        shutil.copyfile(args.floppy, image)
        install(image, "CONFIG.SYS", b"DOS=LOW\r\n", True)
        install(image, "AUTOEXEC.BAT", b"@ECHO OFF\r\nCTTY AUX\r\nWRAP.COM\r\n", True)
        install(image, "WRAP.COM", probe.read_bytes(), True)
        command = ["qemu-system-i386", "-display", "none", "-monitor", "none",
                   "-machine", "pc", "-cpu", "486", "-m", "8", "-nic", "none",
                   "-drive", f"if=floppy,format=raw,file={image}", "-boot", "a",
                   "-serial", "stdio", "-no-reboot",
                   "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
        if mode == "nochain":
            command += ["-d", "nochain"]
        result = subprocess.run(command, capture_output=True, timeout=30)
        log = result.stdout + result.stderr
        (work / (mode + ".log")).write_bytes(log)
        passed = result.returncode == 33 and b"NEAR_CALL_WRAP_PASS" in log
        affected = result.returncode == 35 and b"NEAR_CALL_WRAP_UNMASKED_TARGET" in log
        results[mode] = dict(passed=passed, affected=affected, exit_code=result.returncode)
        print(mode, results[mode])
        assert passed or (mode == "default" and affected and not args.require_default), results
    results["qemu_version"] = subprocess.check_output(["qemu-system-i386", "--version"]).decode().splitlines()[0]
    (work / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
