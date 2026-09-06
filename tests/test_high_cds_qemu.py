#!/usr/bin/env python3
"""Whole-CDS placement: full LASTDRIVE range, I/O/reset and low fallbacks."""

import argparse
import os
from pathlib import Path
import re
import shutil
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
    fixtures = {}
    for name, options in cases:
        log = work / f"{name}.log"
        with log.open("w") as stream:
            result = subprocess.run(common + options, stdout=stream, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError(f"{name} failed: {log}")
        if name in ("lastdrive-Z", "allocation-fallback"):
            matches = re.findall(r"^PASS emm-high: (.+/emm-high\.log)$",
                                 log.read_text(), re.MULTILINE)
            if len(matches) != 1:
                raise RuntimeError(f"cannot identify qualified fixture: {log}")
            fixtures[name] = Path(matches[0]).with_suffix(".img")
        print(f"PASS {name}: {log}", flush=True)

    # The shell suite owns fixed asj-* paths: run sequentially and preserve
    # each serial trace before the next case overwrites it.
    for name, fixture, mode, reject in (
        ("asj-upper", "lastdrive-Z", "upper", False),
        ("asj-low-fallback", "allocation-fallback", "low", False),
        ("asj-reject-low-as-upper", "allocation-fallback", "upper", True),
    ):
        log = work / f"{name}.log"
        env = dict(os.environ, FLOPPY_IMAGE=str(fixtures[fixture]), ASJ_CDS_MODE=mode)
        with log.open("w") as stream:
            result = subprocess.run(["bash", ROOT / "tests/test_assign_subst_join.sh"],
                                    env=env, stdout=stream, stderr=subprocess.STDOUT)
        serial = work / f"{name}-serial.log"
        shutil.copyfile(ROOT / "out/asj-serial.log", serial)
        if reject:
            failures = [line for line in log.read_text().splitlines()
                        if line.startswith("  FAIL:")]
            trace = serial.read_text()
            if (result.returncode == 0
                    or failures != ["  FAIL: CDS upper location/ownership checks"]
                    or trace.count("CDS_LOCATION_FAIL") != 4
                    or "CDS_LOCATION_PASS" in trace):
                raise RuntimeError(f"negative location control did not fail as expected: {log}")
        elif result.returncode:
            raise RuntimeError(f"{name} failed: {log}")
        print(f"PASS {name}: {log}", flush=True)


if __name__ == "__main__":
    main()
