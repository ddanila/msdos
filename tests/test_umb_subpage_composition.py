#!/usr/bin/env python3
"""Measure fine UMBs together with development BIOS/table placement and VC."""

import argparse
import hashlib
import json
import os
import re
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


def xms_summary(serial):
    match = re.search(r"Extended \(XMS\)\s+([\d,]+)\s+([\d,]+)\s+([\d,]+)", serial)
    if not match:
        return None
    total, used, free = (int(value.replace(",", "")) for value in match.groups())
    if used + free != total:
        raise ValueError("inconsistent XMS memory summary")
    return dict(total=total, used=used, free=free)


def paired_inputs(directory):
    """Accept only a completed, non-faulted matched provider fixture."""
    record = json.loads((directory / "result.json").read_text())
    for key in ("common_xms_entry", "reclaim_bootstrap", "high_tables", "fine_umbs", "dos_high"):
        if record.get(key) is not True:
            raise ValueError(f"paired fixture requires {key}")
    for key, value in record.items():
        if (key.startswith("bad_") or key in ("rejected", "table_fallback", "umb_service_reply",
                                             "umb_live_import", "umb_sequence_wrap", "skip_stage_retarget",
                                             "umb_refused_import", "umb_lost_import_reply")) and value:
            raise ValueError(f"fault/instrumentation fixture is not a composed candidate: {key}")
    if record.get("xms_handles") != 32 or set(record.get("post_boot", {})) != {"ON", "OFF", "AUTO", "RAM"}:
        raise ValueError("paired fixture requires the normal capacity and all four completed modes")
    emm, himem = directory / "MEMM/MEMM/EMM386.EXE", directory / "HIMEM.SYS"
    for path, key in ((emm, "trace_emm_sha256"), (himem, "himem_sha256"),
                      (ROOT / "src/DOS/MSDOS.SYS", "dos_sha256"),
                      (ROOT / "src/CMD/COMMAND/COMMAND.COM", "command_sha256")):
        if sha(path.read_bytes()) != record[key]:
            raise ValueError(f"paired fixture binary mismatch: {path}")
    return emm, himem


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, default=ROOT / "out/msdos622-vc405-current-memory.img")
    parser.add_argument("--retail", type=Path, default=ROOT / "out/msdos622-original-vc405.img")
    parser.add_argument("--high-cds", action="store_true", help="also measure complete CDS upper placement")
    parser.add_argument("--high-tables", action="store_true",
                        help="also compose the complete EMM table move with fine UMBs and high CDS")
    parser.add_argument("--paired-provider", type=Path,
                        help="completed fine-UMB/common-provider phase fixture to compose and measure")
    parser.add_argument("--retire-bios-characters", action="store_true",
                        help="retire the complete low character/clock bodies in the paired image")
    args = parser.parse_args()
    paired = paired_inputs(args.paired_provider) if args.paired_provider else None
    if args.retire_bios_characters and not paired:
        parser.error("--retire-bios-characters requires --paired-provider")
    if paired:
        args.high_tables = True
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
    if paired:
        build_bios(work / "bios-paired", early=True, tail_body=True, rebase=True,
                   compact=True, high_cds=True, paired_provider=paired[0],
                   dispatch=args.retire_bios_characters, characters=args.retire_bios_characters,
                   retire_characters=args.retire_bios_characters)
        binaries["paired"] = paired[0]
    assert binaries["coarse"].read_bytes() == (ROOT / "src/MEMM/MEMM/EMM386.EXE").read_bytes()
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    inputs = {}
    for name, emm in binaries.items():
        image = work / f"input-{name}.img"
        shutil.copyfile(args.image, image)
        spec = f"{image}@@{partition_offset(image)}"
        files = {
            "IO.SYS": work / ("bios-paired/IO.SYS" if name == "paired" else
                              "bios-cds/IO.SYS" if name.startswith("fine-cds") else "bios/IO.SYS"),
            "MSDOS.SYS": ROOT / "src/DOS/MSDOS.SYS",
            "COMMAND.COM": ROOT / "src/CMD/COMMAND/COMMAND.COM",
            "DOS/COMMAND.COM": ROOT / "src/CMD/COMMAND/COMMAND.COM",
            "DOS/HIMEM.SYS": paired[1] if name == "paired" else ROOT / "src/DEV/HIMEM/HIMEM.SYS",
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
        serial_log, screen_log = capture(name, image.resolve(), work, probe)
        results[name] = parse_capture(serial_log, screen_log)
        results[name]["xms"] = xms_summary(serial_log.read_text(encoding="latin-1"))
        print(f"Captured {name}: {results[name]['largest']} conventional, {results[name]['upper_free']} UMB", flush=True)
    for name in binaries:
        (work / f"{name}-vs-retail.md").write_text(
            report(results[name], results["retail"], sha(config), sha(vc)) + "\n")
    (work / "results.json").write_text(json.dumps(dict(
        config_sha256=sha(config), vc_sha256=sha(vc),
        input_sha256={name: sha(path.read_bytes()) for name, path in inputs.items()},
        results=results), indent=2) + "\n")
    if paired:
        delta = results["paired"]["largest"] - results["fine-cds-high-tables"]["largest"]
        print(f"MEASURED: paired provider conventional delta {delta:+d} bytes versus composed control", flush=True)
        candidate_xms, control_xms = results["paired"]["xms"], results["fine-cds-high-tables"]["xms"]
        if candidate_xms is None or control_xms is None:
            raise ValueError("paired comparison requires both application XMS summaries")
        if candidate_xms["total"] != control_xms["total"]:
            raise ValueError("paired comparison changed the XMS pool")
        print(f"MEASURED: paired provider free XMS delta {candidate_xms['free'] - control_xms['free']:+d} bytes",
              flush=True)
        # Measurement is deliberately not promotion: no assertion may turn a
        # smaller diagnostic image into an alleged net gain over the control.
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
    if paired:
        with (work / "paired-residency.md").open("w") as census:
            subprocess.run([
                sys.executable, ROOT / "tests/report_dos_bios_residency.py",
                ROOT / "src/DOS/MSDOS.MAP", work / "bios-paired/msBIO.map",
                "--check", "--tail-body", "--boot-manifest", work / "bios-paired/low.json",
                "--command-map", ROOT / "src/CMD/COMMAND/COMMAND.MAP",
                "--composition", work / "results.json", "--variant", "paired",
            ], check=True, stdout=census)
    check_results(results, high_cds=args.high_cds, high_tables=args.high_tables)


def check_results(results, *, high_cds=False, high_tables=False):
    """Validate a completed capture without repeating its emulator runs."""
    assert results["retail"]["largest"] == 618736, results["retail"]
    assert results["retail"]["upper_free"] == 47888, results["retail"]
    # Intact SETVER costs 640 bytes versus the old invalid owner. Recording
    # conventional handle-zero mappings also adds 192 bytes to low EMM tables.
    # XMS zero-length/range correctness adds 32 rounded HIMEM bytes (2640)
    # versus the preceding 2608-byte status/boundary-move checkpoint.
    assert results["coarse"]["largest"] == 613568, results["coarse"]
    assert results["coarse"]["upper_free"] == 47904, results["coarse"]
    assert results["fine"]["largest"] == results["coarse"]["largest"], results
    assert results["fine"]["upper_free"] - results["coarse"]["upper_free"] == 4096, results
    if high_cds:
        assert results["fine-cds"]["largest"] - results["fine"]["largest"] == 2304, results
        assert results["fine"]["upper_free"] - results["fine-cds"]["upper_free"] == 2320, results
        assert results["fine-cds"]["upper_free"] >= results["retail"]["upper_free"], results
    if high_tables:
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
