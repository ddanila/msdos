#!/usr/bin/env python3
"""Observe command-line OFF/AUTO without depending on a private manager ABI."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import shutil
import subprocess
import tempfile

from capture_vc_memory_comparison import ROOT, image_file
from test_dos_char_retirement_qemu import install


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--no-umb", action="store_true")
    parser.add_argument("--emm", type=Path, help="install a candidate manager in the private image")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="emm-off-contract-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    disk = work / "boot.img"
    shutil.copyfile(args.image, disk)
    if args.emm:
        install(disk, "DOS/EMM386.EXE", args.emm.read_bytes())
    if args.no_umb:
        config = image_file(disk, "::CONFIG.SYS")
        config = config.replace(b" RAM", b"").replace(b" NOEMS", b"").replace(b",UMB", b"")
        install(disk, "CONFIG.SYS", config)
    probe = work / "MODE.COM"
    subprocess.run(["nasm", "-f", "bin", ROOT / "tests/emm_mode_status.asm", "-o", probe], check=True)
    install(disk, "MODE.COM", probe.read_bytes())
    install(disk, "QEXIT.COM", (ROOT / "out/command-startup-qexit.com").read_bytes())
    batch = "@ECHO OFF\r\nCTTY AUX\r\nECHO MODE_INITIAL\r\nMODE.COM\r\n"
    for mode in ("OFF", "AUTO", "ON"):
        batch += f"ECHO REQUEST_{mode}\r\nC:\\DOS\\EMM386.EXE {mode}\r\nMODE.COM\r\n"
    batch += "ECHO MODE_SEQUENCE_COMPLETE\r\nQEXIT.COM\r\n"
    install(disk, "AUTOEXEC.BAT", batch.encode("ascii"))
    with (work / "serial.log").open("wb") as log:
        try:
            result = subprocess.run(["qemu-system-i386", "-display", "none", "-monitor", "none",
                "-cpu", "486", "-m", "8", "-boot", "c", "-serial", "stdio", "-no-reboot",
                "-drive", f"if=ide,index=0,format=raw,file={disk}",
                "-debugcon", f"file:{work / 'debug.log'}", "-global", "isa-debugcon.iobase=0xe9",
                "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
                stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, timeout=45)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = None
    serial = (work / "serial.log").read_text(encoding="latin-1")
    report = dict(exit_code=code, no_umb=args.no_umb, serial=serial,
        sha256={name: hashlib.sha256(image_file(disk, "::" + name)).hexdigest()
                for name in ("IO.SYS", "MSDOS.SYS", "COMMAND.COM", "DOS/EMM386.EXE", "CONFIG.SYS")})
    (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(serial, flush=True)
    assert code == 33 and "MODE_SEQUENCE_COMPLETE" in serial, code
    assert re.findall(r"CPU_PE=([01])", serial) == (
        ["1", "0", "0", "1"] if args.no_umb else ["1"] * 4), serial
    if not args.no_umb:
        off = serial.split("REQUEST_OFF", 1)[1].split("REQUEST_AUTO", 1)[0]
        assert "Unable" in off, "OFF was not explicitly refused"


if __name__ == "__main__":
    main()
