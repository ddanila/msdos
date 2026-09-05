#!/usr/bin/env python3
"""Boot the combined inactive BIOS in low/high and standalone/EMM configurations."""
import os
import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path

from build_bios_low_image import ROOT, build, run
from build_bios_high_payload import build as build_high
from build_bios_activation_fixture import write_fixture


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--early", action="store_true", help="activate during SYSINIT, before buffers and COMMAND")
    parser.add_argument("--tail-body", action="store_true", help="test last-linked fallback service layout")
    parser.add_argument("--scan", action="store_true", help="record activation-time pointer candidates on debug port")
    parser.add_argument("--rebase", action="store_true", help="move and poison the old low DOS prefix")
    parser.add_argument("--compact", action="store_true", help="move the HIMEM boot allocation after rebasing")
    parser.add_argument("--fail-reservation", action="store_true", help="force the early capacity check to reject")
    parser.add_argument("--mode", action="append", help="run only this mode; repeat as needed")
    args = parser.parse_args()
    if args.fail_reservation and not args.early:
        parser.error("--fail-reservation requires --early")
    if (args.scan or args.rebase) and not (args.early and args.tail_body):
        parser.error("--scan/--rebase requires --early --tail-body")
    if args.compact and not args.rebase:
        parser.error("--compact requires --rebase")
    scratch = Path(tempfile.mkdtemp(prefix="bios-low-boot-", dir=ROOT / "out"))
    manifest = build(scratch, early=args.early, tail_body=args.tail_body, scan=args.scan, rebase=args.rebase, compact=args.compact,
                     reservation_limit=0x10 if args.fail_reservation else 0xfff0)
    high_manifest = build_high(scratch / "high", scratch)
    write_fixture(scratch, manifest, high_manifest)
    if high_manifest["low_image_sha256"] != manifest["sha256"]:
        raise RuntimeError("high payload was bound against a different low BIOS")
    # Every named low gate/helper imported by the high payload now exists in
    # this combined image. The owner segment is supplied by the future loader.
    for slot in high_manifest["runtime_slots"].values():
        if slot["target"] != "resident low BIOS segment":
            if slot["target"].upper() not in manifest["symbols"]:
                raise RuntimeError(f"missing production low binding: {slot['target']}")
    (scratch / "low-defs.inc").write_text(
        f"ACTIVE_OFFSET equ {manifest['symbols']['BIOS_SERVICE_ACTIVE']}\n"
        f"SERVICE_START equ {manifest['symbols']['BIOS_SERVICE_START']}\n"
        f"SERVICE_SIZE equ {manifest['symbols']['BIOS_SERVICE_END'] - manifest['symbols']['BIOS_SERVICE_START']}\n"
        f"SLOT_WORD_COUNT equ {len(manifest['high_slot_words'])}\n")
    if args.tail_body:
        with (scratch / "low-defs.inc").open("a") as stream:
            stream.write(f"PERMANENT_END_OFFSET equ {manifest['symbols']['BIOS_PERMANENT_END']}\n")
    (scratch / "low-slots.inc").write_text(
        "dw " + ",".join(map(str, manifest["high_slot_words"])) + "\n")
    variants = {
        "bare-low": (False, "DOS=LOW\r\n"),
        "himem-low": (False, "DEVICE=HIMEM.SYS /TESTMEM:OFF\r\nDOS=LOW\r\n"),
        "himem-high": (True, "DEVICE=HIMEM.SYS /TESTMEM:OFF\r\nDOS=HIGH\r\n"),
        "emm-high": (True, "DEVICE=HIMEM.SYS /TESTMEM:OFF\r\n"
                     "DEVICE=EMM386.EXE RAM\r\nDOS=HIGH,UMB\r\n"),
    }
    if args.rebase:
        # Exercise CONFIG parsing after the pointer move, including its cached
        # DOS NLS/DBCS table addresses. Default values would hide lost directives.
        variants = {name: (high, config + "LASTDRIVE=Z\r\nFILES=20\r\nFCBS=4,0\r\nBUFFERS=15\r\n")
                    for name, (high, config) in variants.items()}
    if not args.early:
        variants["live-himem"] = variants["himem-high"]
        variants["live-emm"] = variants["emm-high"]
        variants["live-stale-entry"] = variants["himem-high"]
    if args.mode:
        unknown = set(args.mode) - variants.keys()
        if unknown:
            parser.error("unknown mode(s): " + ", ".join(sorted(unknown)))
        variants = {name: config for name, config in variants.items() if name in args.mode}
    env = {**os.environ, "MTOOLS_SKIP_CHECK": "1"}
    for name, (high, config) in variants.items():
        probe = scratch / f"{name}.com"
        options = ["-DACTIVATE_HIGH"] if name.startswith("live-") else []
        if args.rebase:
            options.append(f"-DEXPECT_REBASE={int(high and not args.fail_reservation)}")
            options.append("-DEXPECT_CDS=26")
        if args.compact:
            options.append("-DEXPECT_COMPACT")
        negative = name == "live-stale-entry"
        if negative:
            options.append("-DOMIT_LIVE_PUBLICATION")
        run(["nasm", "-f", "bin", f"-I{scratch}/", f"-I{ROOT / 'tests'}/",
             f"-DEXPECT_HIGH={int(high)}",
             f"-DEXPECT_ACTIVE={int(args.early and high and not args.fail_reservation)}", *options,
             ROOT / "tests/bios_low_boot_probe.asm", "-o", probe], ROOT)
        image = scratch / f"{name}.img"
        shutil.copyfile(ROOT / "out/floppy.img", image)
        for source, destination in ((scratch / "IO.SYS", "IO.SYS"), (probe, "LOWBOOT.COM")):
            subprocess.run(["mcopy", "-o", "-i", str(image), str(source), f"::{destination}"],
                           env=env, check=True)
        for destination, text in (("CONFIG.SYS", config), ("AUTOEXEC.BAT",
                                  "@ECHO OFF\r\nCTTY AUX\r\nLOWBOOT.COM\r\n")):
            subprocess.run(["mcopy", "-o", "-i", str(image), "-", f"::{destination}"],
                           input=text.encode(), env=env, check=True)
        log = scratch / f"{name}.log"
        with log.open("wb") as stream:
            debug_options = (["-debugcon", f"file:{scratch / (name + '.scan')}",
                              "-global", "isa-debugcon.iobase=0xe9"] if args.scan else [])
            try:
                subprocess.run(["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
                                "-display", "none", "-monitor", "none", "-serial", "stdio",
                                "-boot", "a", "-no-reboot", *debug_options, "-device",
                                "isa-debug-exit,iobase=0xf4,iosize=0x04", "-drive",
                                f"if=floppy,index=0,format=raw,file={image},cache=writethrough"],
                               stdout=stream, stderr=subprocess.STDOUT, timeout=35)
            except subprocess.TimeoutExpired:
                pass
        result = log.read_bytes()
        passed = b"BIOS_LOW_BOOT_PASS" in result
        if (passed == negative or (passed and b"BIOS_LOW_BOOT_FAIL" in result)
                or (name.startswith("live-") and b"BIOS_LIVE_READY" not in result)):
            raise RuntimeError(f"FAIL {name}: {log}\n{result.decode(errors='replace')}")
        print(f"PASS {name}: {log}", flush=True)
        if args.scan:
            scan_path = scratch / (name + ".scan")
            if high and not args.fail_reservation:
                from report_bios_rebase_scan import report
                report(scan_path, ROOT / "src/DOS/MSDOS.MAP", scratch / "msBIO.map",
                       scratch / (name + "-scan.md"))
            elif scan_path.read_bytes():
                raise RuntimeError("inactive boot unexpectedly recorded an activation census")


if __name__ == "__main__":
    main()
