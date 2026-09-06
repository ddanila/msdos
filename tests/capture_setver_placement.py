#!/usr/bin/env python3
"""Read-only SETVER table/filename witness on a private copy of a boot image.

Use --preserve-config for a development image already configured DOS-high;
the default replaces CONFIG.SYS with DOS=LOW. No SETVER edits are performed.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--preserve-config", action="store_true")
    parser.add_argument("--check", action="store_true",
                        help="fail unless both tables match defaults and filename versions are correct")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="setver-placement-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    image = work / "boot.img"
    shutil.copyfile(args.image, image)
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1")

    def run(command, **kwargs):
        return subprocess.run(command, env=env, check=True, **kwargs)

    probe = work / "probe.com"
    exit_com = work / "exit.com"
    run(["nasm", "-f", "bin", f"-I{ROOT / 'src/INC'}/",
         ROOT / "tests/setver_table_probe.asm", "-o", probe])
    run(["nasm", "-f", "bin", ROOT / "tests/qemu_exit.asm", "-o", exit_com])
    for source, name in ((probe, "REFVER.COM"), (probe, "ASSIGN.COM"), (exit_com, "QEXIT.COM")):
        run(["mcopy", "-o", "-i", image, source, f"::{name}"])
    if not args.preserve_config:
        run(["mcopy", "-o", "-i", image, "-", "::CONFIG.SYS"], input=b"DOS=LOW\r\n")
    config = run(["mtype", "-i", image, "::CONFIG.SYS"], capture_output=True).stdout
    (work / "config.sys").write_bytes(config)
    run(["mcopy", "-o", "-i", image, "-", "::AUTOEXEC.BAT"],
        input=b"@ECHO OFF\r\nCTTY AUX\r\nREFVER.COM\r\nASSIGN.COM\r\nQEXIT.COM\r\n")
    with (work / "serial.log").open("wb") as output:
        result = subprocess.run(["qemu-system-i386", "-machine", "pc", "-cpu", "486",
                                 "-m", "8", "-display", "none", "-monitor", "none",
                                 "-serial", "stdio", "-no-reboot", "-boot", "a",
                                 "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
                                 "-drive", f"if=floppy,format=raw,file={image},cache=writethrough"],
                                stdout=output, stderr=subprocess.STDOUT, timeout=35)
    trace = (work / "serial.log").read_text()
    if result.returncode != 33 or trace.count("SETVER_TABLE_PROBE_END") != 2:
        raise RuntimeError(f"probe did not complete: {work / 'serial.log'}")
    versions = re.findall(r"SETVER_REPORTED_AX\n([0-9A-F]{4})", trace)
    tables = re.findall(r"SETVER_TABLE_SEG_OFF_CAP\n([0-9A-F]{4})\n([0-9A-F]{4})\n([0-9A-F]{4})", trace)
    valid = (len(tables) == 2 and trace.count("SETVER_DEFAULT_TABLE_PASS") == 2
             and versions == ["1606", "0005"])
    report = {"input_sha256": hashlib.sha256(args.image.read_bytes()).hexdigest(),
              "preserved_config": args.preserve_config, "tables": tables,
              "versions_refver_assign": versions, "default_table_matches": trace.count("SETVER_DEFAULT_TABLE_PASS"),
              "first_difference_offsets": re.findall(r"SETVER_FIRST_DIFFERENCE\n([0-9A-F]{4})", trace),
              "qualified": valid}
    (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if args.check and not valid:
        raise SystemExit("SETVER placement is not qualified; see the retained report")


if __name__ == "__main__":
    main()
