#!/usr/bin/env python3
"""Qualify the installed BIOS PS/2 status-reset branch, not PS/2 hardware."""
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
    parser.add_argument("image", type=Path)
    parser.add_argument("bios_directory", type=Path)
    args = parser.parse_args()
    low = json.loads((args.bios_directory / "low.json").read_text())
    high = json.loads((args.bios_directory / "high/bios-high.json").read_text())
    bios = image_file(args.image, "::IO.SYS")
    assert hashlib.sha256(bios).hexdigest() == low["sha256"] == high["low_image_sha256"]
    assert low["retired_ioctl_state"] and high["retired_ioctl_state"]
    payload = (args.bios_directory / "high/bios-high.bin").read_bytes()
    assert hashlib.sha256(payload).hexdigest() == high["sha256"]
    lo, hi = low["symbols"], high["exports"]
    instruction = b"\x2e\x8b\x16" + hi["PREV_DX"].to_bytes(2, "little")
    assert payload.count(instruction) == 1
    restore = payload.index(instruction)
    assert hi["BLOCK13"] < restore < hi["BIOS_SERVICE_END"]
    work = Path(tempfile.mkdtemp(prefix="bios-ps2-status-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    definitions = dict(ACTIVE=lo["BIOS_SERVICE_ACTIVE"], MODEL=lo["MODEL_BYTE"],
                       ORIG13=lo["ORIG13"], LOW_ENTRY=lo["BIOS_LOW_BLOCK13"],
                       HIGH_ENTRY=lo["BIOS_HIGH_BLOCK13_ENTRY"], HIGH_BLOCK13=hi["BLOCK13"],
                       RESTORE_OFFSET=restore)
    report = dict(input_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest(),
                  bios_sha256=low["sha256"], definitions=definitions,
                  source_sha256={str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in (Path(__file__), ROOT / "tests/bios_ps2_status.asm")}, results=[])
    for name, negative in (("good", False), ("missing-drive-restore", True)):
        disk = work / f"{name}.img"
        shutil.copyfile(args.image, disk)
        probe = work / f"{name}.com"
        subprocess.run(["nasm", "-f", "bin", *[f"-D{k}={v}" for k, v in definitions.items()],
                        *(["-DOMIT_RESTORE"] if negative else []),
                        ROOT / "tests/bios_ps2_status.asm", "-o", probe], check=True)
        install(disk, "PS2TEST.COM", probe.read_bytes())
        install(disk, "AUTOEXEC.BAT", b"@ECHO OFF\r\nCTTY AUX\r\nPS2TEST.COM\r\n")
        with (work / f"{name}.log").open("wb") as log:
            try:
                result = subprocess.run(["qemu-system-i386", "-display", "none", "-monitor", "none",
                    "-cpu", "486", "-m", "8", "-boot", "c", "-serial", "stdio", "-no-reboot",
                    "-drive", f"if=ide,index=0,format=raw,file={disk}",
                    "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
                    stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, timeout=40)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = None
        serial = (work / f"{name}.log").read_text(encoding="latin-1")
        passed = code == (35 if negative else 33) and (
            "BIOS_PS2_STATUS_FAIL" if negative else "BIOS_PS2_STATUS_PASS") in serial
        report["results"].append(dict(case=name, exit_code=code, passed=passed,
                                     probe_sha256=hashlib.sha256(probe.read_bytes()).hexdigest()))
        (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        assert passed, (name, code, serial)
        print(f"{name}: PASS", flush=True)


if __name__ == "__main__":
    main()
