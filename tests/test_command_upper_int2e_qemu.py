#!/usr/bin/env python3
"""INT 2Eh pending-tail and caller/stack ownership in the packed composition."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from capture_vc_memory_comparison import ROOT, image_file
from test_dos_char_retirement_qemu import install


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="composed image with packed upper-data COMMAND")
    parser.add_argument("--manager-modes", action="store_true", help="repeat across ON/OFF/AUTO/ON")
    parser.add_argument("--a20-off", action="store_true", help="prove A20 aliasing immediately before INT 2Eh")
    parser.add_argument("--low-paragraphs", type=int, default=34,
                        help="expected main owner; use 55 for the pre-retirement control")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="command-upper-int2e-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    report = dict(command_sha256=hashlib.sha256(image_file(args.image, "::COMMAND.COM")).hexdigest(),
                  manager_modes=args.manager_modes, a20_off=args.a20_off,
                  low_paragraphs=args.low_paragraphs, results=[])
    cases = ["good", "wrong-stack"] + (["a20-not-disabled"] if args.a20_off else [])
    for label in cases:
        negative = label != "good"
        disk = work / (label + ".img")
        shutil.copyfile(args.image, disk)
        probe = work / (label + ".com")
        defines = ["-DEXPECT_HMA=1", f"-DEXPECT_LOW_PARAGRAPHS={args.low_paragraphs}"]
        if label == "wrong-stack":
            defines.append("-DEXPECT_CALLER_STACK")
        if args.manager_modes:
            defines.append("-DEXPECT_MANAGER_MODES")
        if args.a20_off:
            defines.append("-DEXPECT_A20_OFF")
        if label == "a20-not-disabled":
            defines.append("-DA20_SKIP_DISABLE")
        subprocess.run(["nasm", "-f", "bin", *defines,
                        ROOT / "tests/command_int2e_owner_probe.asm", "-o", probe], check=True)
        install(disk, "I2EOWNER.COM", probe.read_bytes())
        # Old output must not turn a failed command dispatch into a pass.
        for name in ("I2EINT.TXT", "I2EEXT.TXT"):
            install(disk, name, b"STALE_OUTPUT_MUST_BE_REPLACED\r\n")
        install(disk, "AUTOEXEC.BAT", b"@ECHO OFF\r\nCTTY AUX\r\nI2EOWNER.COM\r\n")
        with (work / (label + ".log")).open("wb") as log:
            try:
                result = subprocess.run(["qemu-system-i386", "-display", "none", "-monitor", "none",
                    "-cpu", "486", "-m", "8", "-boot", "c", "-serial", "stdio", "-no-reboot",
                    "-drive", f"if=ide,index=0,format=raw,file={disk}",
                    "-debugcon", f"file:{work / (label + '.debug')}",
                    "-global", "isa-debugcon.iobase=0xe9",
                    "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
                    stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, timeout=45)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = None
        serial = (work / (label + ".log")).read_text(encoding="latin-1")
        marker = "COMMAND_INT2E_OWNER_" + ("FAIL" if negative else "PASS")
        passed = code == (35 if negative else 33) and marker in serial
        report["results"].append(dict(case=label, exit_code=code, passed=passed))
        (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        assert passed, (label, code, serial)
    print("Packed INT 2Eh ownership and wrong-stack control: PASS", flush=True)


if __name__ == "__main__":
    main()
