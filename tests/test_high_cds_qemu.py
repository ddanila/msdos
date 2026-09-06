#!/usr/bin/env python3
"""Whole-CDS placement: full LASTDRIVE range, I/O/reset and low fallbacks."""

import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
from test_umb_subpage_discovery_qemu import ROOT, build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quick", action="store_true", help="use LASTDRIVE=Z only; omit the A..Y matrix")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="high-cds-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    emm = build(work / "emm", True, "-DUMB_SUBPAGE_MAPPING")
    common = [sys.executable, str(ROOT / "tests/test_bios_low_boot_qemu.py"),
              "--early", "--tail-body", "--rebase", "--compact", "--high-cds",
              "--emm386-image", str(emm)]
    cases = [(f"lastdrive-{letter}", ["--mode", "emm-high", "--lastdrive", letter])
             for letter in ("Z" if args.quick else "ABCDEFGHIJKLMNOPQRSTUVWXYZ")]
    cases += [(f"io-{size}", ["--mode", "emm-high", "--umb-read", "--umb-ems",
                              "--umb-span", str(size), "--warm-reset"]) for size in (12, 32)]
    cases += [
        ("allocation-fallback", ["--mode", "emm-high", "--fail-cds-allocation",
                                 "--umb-read", "--umb-ems", "--warm-reset"]),
        ("low-fallbacks", ["--mode", "bare-low", "--mode", "himem-low", "--mode", "himem-high"]),
    ]
    for name, options in cases:
        log = work / f"{name}.log"
        with log.open("w") as stream:
            result = subprocess.run(common + options, stdout=stream, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError(f"{name} failed: {log}")
        print(f"PASS {name}: {log}", flush=True)


if __name__ == "__main__":
    main()
