#!/usr/bin/env python3
"""Force transient reload after SET COMSPEC and check the real reload prompt."""
import argparse
import json
from itertools import product
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from test_command_high_resident_qemu import ROOT, run, sha


def check(command, floppy, work):
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    probe = work / "PIPEIO.COM"
    run(["nasm", "-f", "bin", ROOT / "tests/command_pipe_filter.asm", "-o", probe])
    results = []
    paths = (("relative", "MISSING.COM", "MISSING.COM"),
             ("drive", "A:\\MISSING.COM", "\\MISSING.COM"))
    for mode, (case, value, displayed) in product(("HIGH", "LOW"), paths):
        label = f"{mode}-{case}"
        disk = work / f"{label}.img"
        shutil.copyfile(floppy, disk)
        for source, target in ((command, "COMMAND.COM"), (probe, "PIPEIO.COM")):
            run(["mcopy", "-o", "-i", disk, source, "::"+target], env=env)
        files = {
            "CONFIG.SYS": f"DEVICE=A:\\HIMEM.SYS\r\nDOS={mode}\r\nBUFFERS=15\r\n",
            "AUTOEXEC.BAT": f"@ECHO OFF\r\nCTTY AUX\r\nSET COMSPEC={value}\r\n"
                            "ECHO RELOAD_INPUT|PIPEIO\r\nECHO UNEXPECTED_RELOAD\r\n",
        }
        for name, contents in files.items():
            run(["mcopy", "-o", "-i", disk, "-", "::"+name],
                input=contents.encode("ascii"), env=env)
        # A missing shell must wait for replacement media; do not supply a key.
        try:
            result = subprocess.run(["qemu-system-i386", "-display", "none", "-monitor", "none",
                "-cpu", "486", "-m", "8", "-boot", "a", "-serial", "stdio", "-no-reboot",
                "-drive", f"if=floppy,index=0,format=raw,file={disk}"],
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
            output, timed_out = result.stdout, False
        except subprocess.TimeoutExpired as error:
            output, timed_out = error.stdout or b"", True
        (work / f"{label}.log").write_bytes(output)
        expected = f"Insert disk with {displayed} in drive A\r\n".encode("ascii")
        passed = (timed_out and b"PIPE_FILTER_OVERWRITE" in output
                  and expected in output
                  and b"UNEXPECTED_RELOAD" not in output)
        results.append(dict(mode=mode, case=case, passed=passed, timed_out=timed_out))
    (work / "results.json").write_text(json.dumps(dict(command_sha256=sha(command),
        floppy_sha256=sha(floppy), results=results), indent=2)+"\n")
    assert all(row["passed"] for row in results), results


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", type=Path)
    parser.add_argument("--floppy", type=Path, default=ROOT / "out/floppy.img")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="command-comspec-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    check(args.command.resolve(), args.floppy.resolve(), work)
