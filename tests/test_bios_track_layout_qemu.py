#!/usr/bin/env python3
"""Exercise real floppy formatting and subsequent I/O in a composed HDD boot."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from capture_vc_memory_comparison import ROOT
from test_dos_char_retirement_qemu import install


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="bios-track-layout-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    results = []
    for sectors in (2880, 5760):
        disk = work / f"boot-{sectors}.img"
        floppy = work / f"floppy-{sectors}.img"
        shutil.copyfile(args.image, disk)
        floppy.write_bytes(bytes(sectors * 512))
        install(disk, "QEXIT.COM", (ROOT / "out/command-startup-qexit.com").read_bytes())
        batch = ("@ECHO OFF\r\nCTTY AUX\r\n"
                 "C:\\DOS\\FORMAT.COM A: /U /AUTOTEST /V:TRACK\r\n"
                 "IF ERRORLEVEL 1 ECHO TRACK_FORMAT_FAILED\r\n"
                 "ECHO TRACK_DATA_SURVIVED>A:\\TRACK.TXT\r\n"
                 "TYPE A:\\TRACK.TXT\r\nECHO TRACK_SEQUENCE_COMPLETE\r\nQEXIT.COM\r\n")
        install(disk, "AUTOEXEC.BAT", batch.encode("ascii"))
        with (work / f"{sectors}.log").open("wb") as log:
            try:
                result = subprocess.run(["qemu-system-i386", "-display", "none", "-monitor", "none",
                    "-cpu", "486", "-m", "8", "-boot", "c", "-serial", "stdio", "-no-reboot",
                    "-drive", f"if=ide,index=0,format=raw,file={disk}",
                    "-drive", f"if=floppy,index=0,format=raw,file={floppy}",
                    "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
                    input=b"N\r", stdout=log, stderr=subprocess.STDOUT, timeout=60)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = None
        serial = (work / f"{sectors}.log").read_text(encoding="latin-1")
        passed = (code == 33 and "TRACK_SEQUENCE_COMPLETE" in serial
                  and "TRACK_DATA_SURVIVED" in serial and "TRACK_FORMAT_FAILED" not in serial
                  and "100 percent of disk formatted" in serial)
        results.append(dict(sectors=sectors, exit_code=code, passed=passed))
        (work / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        assert passed, (sectors, code, serial)
        print(f"{sectors} sectors: PASS", flush=True)


if __name__ == "__main__":
    main()
