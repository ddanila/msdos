#!/usr/bin/env python3
"""Require both reboot fixes with same-size, one-owner negative controls."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile

from build_bios_low_image import ROOT
from capture_vc_memory_comparison import image_file
from test_dos_char_retirement_qemu import install


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("bios", type=Path, help="matching IO.SYS, MSBIO.BIN and low.json")
    parser.add_argument("emm", type=Path, help="matching EMM386.EXE and EMM386.MAP")
    args = parser.parse_args()
    io = image_file(args.image, "::IO.SYS")
    emm = image_file(args.image, "::DOS/EMM386.EXE")
    assert io == (args.bios / "IO.SYS").read_bytes()
    assert emm == (args.emm / "EMM386.EXE").read_bytes()
    manifest = json.loads((args.bios / "low.json").read_text())
    assert hashlib.sha256(io).hexdigest() == manifest["sha256"]
    assert hashlib.sha256(emm).hexdigest() == manifest["paired_provider_sha256"]
    body = (args.bios / "MSBIO.BIN").read_bytes()
    assert io.endswith(body)
    start = len(io) - len(body) + manifest["symbols"]["INT19"]
    count = io.index(b"\xb9\x11\0", start, start + 64)
    no_vectors = bytearray(io)
    no_vectors[count + 1] = 14  # keep hardware-vector cleanup; omit service vectors
    match = re.search(r"^([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4})\s+i19_Entry$",
                      (args.emm / "EMM386.MAP").read_text(), re.MULTILINE)
    assert match
    entry = (struct.unpack_from("<H", emm, 8)[0] * 16
             + int(match[1], 16) * 16 + int(match[2], 16))
    assert emm[entry:entry + 10] == b"\x50\xb0\x0f\xe6\x84\xb0\0\xe6\x85\x58"
    no_exit = bytearray(emm)
    no_exit[entry + 3:entry + 5] = b"\x90\x90"  # omit the first return-real handshake
    work = Path(tempfile.mkdtemp(prefix="software-reboot-guards-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    cases = []
    for name, target, data in (("positive", None, None),
                               ("no-service-vectors", "IO.SYS", no_vectors),
                               ("no-real-exit", "DOS/EMM386.EXE", no_exit)):
        disk = work / f"{name}.img"
        shutil.copyfile(args.image, disk)
        if target:
            install(disk, target, data)
        cases.append((name, disk))

    def run(case):
        name, disk = case
        result = subprocess.run([sys.executable, ROOT / "tests/test_software_reboot_qemu.py", disk],
                                capture_output=True, text=True)
        (work / f"{name}.log").write_text(result.stdout + result.stderr)
        report = json.loads(result.stdout.split("\n", 1)[1])
        assert report["first_boots"] == 1, (name, report)
        if name == "positive":
            assert result.returncode == 0 and report["passed"], report
        else:
            assert result.returncode == 1 and not report["passed"], (name, report)
            assert report["second_boots"] == 0, (name, report)
        print(f"PASS {name}: {report['elapsed_seconds']} seconds", flush=True)
        return name, report

    with ThreadPoolExecutor(max_workers=2) as pool:
        reports = dict(pool.map(run, cases))
    (work / "results.json").write_text(json.dumps(reports, indent=2) + "\n")


if __name__ == "__main__":
    main()
