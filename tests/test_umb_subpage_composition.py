#!/usr/bin/env python3
"""Measure fine UMBs together with development BIOS/table placement and VC."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from build_bios_low_image import build as build_bios
from capture_vc_memory_comparison import capture, image_file, parse_capture, partition_offset, report
from test_umb_subpage_discovery_qemu import ROOT, build as build_emm, run


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, default=ROOT / "out/msdos622-vc405-current-memory.img")
    parser.add_argument("--retail", type=Path, default=ROOT / "out/msdos622-original-vc405.img")
    parser.add_argument("--high-cds", action="store_true", help="also measure complete CDS upper placement")
    parser.add_argument("--high-tables", action="store_true",
                        help="also compose the complete EMM table move with fine UMBs and high CDS")
    args = parser.parse_args()
    if args.high_tables:
        args.high_cds = True
    for path in (args.image, args.retail):
        if not path.is_file():
            parser.error(f"missing fixed comparison image: {path}")
    config = image_file(args.image, "::CONFIG.SYS").replace(b"\r\n", b"\n")
    vc = image_file(args.image, "::VC/VC.COM")
    assert config == image_file(args.retail, "::CONFIG.SYS").replace(b"\r\n", b"\n")
    assert vc == image_file(args.retail, "::VC/VC.COM")
    work = Path(tempfile.mkdtemp(prefix="umb-fine-composition-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    build_bios(work / "bios", early=True, tail_body=True, rebase=True, compact=True)
    binaries = {"coarse": build_emm(work / "emm-coarse", False),
                "fine": build_emm(work / "emm-fine", True, "-DUMB_SUBPAGE_MAPPING")}
    if args.high_cds:
        build_bios(work / "bios-cds", early=True, tail_body=True, rebase=True, compact=True, high_cds=True)
        binaries["fine-cds"] = binaries["fine"]
    if args.high_tables:
        binaries["fine-cds-high-tables"] = build_emm(
            work / "emm-high-tables", True, "-DUMB_SUBPAGE_MAPPING", high_tables=True)
    assert binaries["coarse"].read_bytes() == (ROOT / "src/MEMM/MEMM/EMM386.EXE").read_bytes()
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    inputs = {}
    for name, emm in binaries.items():
        image = work / f"input-{name}.img"
        shutil.copyfile(args.image, image)
        spec = f"{image}@@{partition_offset(image)}"
        files = {
            "IO.SYS": work / ("bios-cds/IO.SYS" if name.startswith("fine-cds") else "bios/IO.SYS"),
            "MSDOS.SYS": ROOT / "src/DOS/MSDOS.SYS",
            "COMMAND.COM": ROOT / "src/CMD/COMMAND/COMMAND.COM",
            "DOS/COMMAND.COM": ROOT / "src/CMD/COMMAND/COMMAND.COM",
            "DOS/HIMEM.SYS": ROOT / "src/DEV/HIMEM/HIMEM.SYS",
            "DOS/EMM386.EXE": emm,
        }
        for destination, source in files.items():
            run(["mcopy", "-o", "-i", spec, source, "::" + destination], env=env)
            assert image_file(image, "::" + destination) == source.read_bytes()
        assert image_file(image, "::CONFIG.SYS").replace(b"\r\n", b"\n") == config
        assert image_file(image, "::VC/VC.COM") == vc
        inputs[name] = image
    probe = work / "CEILING.COM"
    run(["nasm", "-f", "bin", ROOT / "tests/memory_ceiling_probe.asm", "-o", probe])
    results = {}
    inputs["retail"] = args.retail
    for name, image in inputs.items():
        results[name] = parse_capture(*capture(name, image.resolve(), work, probe))
        print(f"Captured {name}: {results[name]['largest']} conventional, {results[name]['upper_free']} UMB", flush=True)
    for name in binaries:
        (work / f"{name}-vs-retail.md").write_text(
            report(results[name], results["retail"], sha(config), sha(vc)) + "\n")
    (work / "results.json").write_text(json.dumps(dict(
        config_sha256=sha(config), vc_sha256=sha(vc),
        input_sha256={name: sha(path.read_bytes()) for name, path in inputs.items()},
        results=results), indent=2) + "\n")
    if args.high_cds:
        with (work / "joint-residency.md").open("w") as census:
            subprocess.run([
                sys.executable, ROOT / "tests/report_dos_bios_residency.py",
                ROOT / "src/DOS/MSDOS.MAP", work / "bios-cds/msBIO.map",
                "--check", "--tail-body", "--boot-manifest", work / "bios-cds/low.json",
                "--command-map", ROOT / "src/CMD/COMMAND/COMMAND.MAP",
                "--composition", work / "results.json", "--variant",
                "fine-cds-high-tables" if args.high_tables else "fine-cds",
            ], check=True, stdout=census)
    assert results["retail"]["largest"] == 618736, results["retail"]
    assert results["retail"]["upper_free"] == 47888, results["retail"]
    # Intact SETVER costs 640 bytes versus the old invalid owner. Recording
    # conventional handle-zero mappings also adds 192 bytes to low EMM tables.
    assert results["coarse"]["largest"] == 613616, results["coarse"]
    assert results["coarse"]["upper_free"] == 47904, results["coarse"]
    assert results["fine"]["largest"] == results["coarse"]["largest"], results
    assert results["fine"]["upper_free"] - results["coarse"]["upper_free"] == 4096, results
    if args.high_cds:
        assert results["fine-cds"]["largest"] - results["fine"]["largest"] == 2304, results
        assert results["fine"]["upper_free"] - results["fine-cds"]["upper_free"] == 2320, results
        assert results["fine-cds"]["upper_free"] >= results["retail"]["upper_free"], results
    if args.high_tables:
        candidate, previous = results["fine-cds-high-tables"], results["fine-cds"]
        assert candidate["largest"] > previous["largest"], results
        assert candidate["upper_free"] == previous["upper_free"], results
        assert candidate["upper_free"] >= results["retail"]["upper_free"], results
        print(f"PASS: complete EMM tables reclaim {candidate['largest'] - previous['largest']} "
              "conventional bytes without consuming free UMB", flush=True)
        print("PASS: complete CDS move reclaims 2304 conventional bytes within the retail UMB floor", flush=True)
    print("PASS: combined layout retains conventional memory and gains 4096 free UMB bytes", flush=True)


if __name__ == "__main__":
    main()
