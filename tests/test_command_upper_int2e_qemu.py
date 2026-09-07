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
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="command-upper-int2e-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    report = dict(command_sha256=hashlib.sha256(image_file(args.image, "::COMMAND.COM")).hexdigest(),
                  results=[])
    for negative in (False, True):
        label = "wrong-stack" if negative else "good"
        disk = work / (label + ".img")
        shutil.copyfile(args.image, disk)
        probe = work / (label + ".com")
        defines = ["-DEXPECT_HMA=1", "-DEXPECT_LOW_PARAGRAPHS=34"]
        if negative:
            defines.append("-DEXPECT_CALLER_STACK")
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
