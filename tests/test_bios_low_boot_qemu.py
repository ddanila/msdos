#!/usr/bin/env python3
"""Boot the combined inactive BIOS in low/high and standalone/EMM configurations."""
import os
import argparse
import shutil
import subprocess
import struct
import socket
import json
import re
import time
import tempfile
from pathlib import Path

from build_bios_low_image import ROOT, build, run
from build_bios_high_payload import build as build_high
from build_bios_activation_fixture import write_fixture


def run_warm_reset(command, log, stream, qmp_path):
    """Reset only a verified live guest stopped after its first successful pass."""
    process = subprocess.Popen(command + ["-qmp", f"unix:{qmp_path},server=on,wait=off"],
                               stdout=stream, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic() + 35
        while b"BIOS_WARM_RESET_READY" not in log.read_bytes():
            if process.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError(f"guest did not reach reset boundary: {log}")
            time.sleep(0.05)
        if process.poll() is not None:
            raise RuntimeError("guest exited before reset")
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(5)
            connection.connect(str(qmp_path))
            with connection.makefile("rwb") as protocol:
                if "QMP" not in json.loads(protocol.readline()):
                    raise RuntimeError("missing QMP greeting")
                for operation in ("qmp_capabilities", "system_reset"):
                    protocol.write(json.dumps({"execute": operation, "id": operation}).encode() + b"\n")
                    protocol.flush()
                    while True:
                        reply = json.loads(protocol.readline())
                        if reply.get("id") == operation:
                            if "return" not in reply:
                                raise RuntimeError(f"QMP rejected {operation}: {reply}")
                            break
        process.wait(timeout=35)
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--early", action="store_true", help="activate during SYSINIT, before buffers and COMMAND")
    parser.add_argument("--tail-body", action="store_true", help="test last-linked fallback service layout")
    parser.add_argument("--scan", action="store_true", help="record activation-time pointer candidates on debug port")
    parser.add_argument("--rebase", action="store_true", help="move and poison the old low DOS prefix")
    parser.add_argument("--compact", action="store_true", help="move the HIMEM boot allocation after rebasing")
    parser.add_argument("--warm-reset", action="store_true", help="repeat the full probe across a QMP hardware reset")
    parser.add_argument("--stale-cds-control", action="store_true", help="require rejection of a deliberately stale external CDS pointer")
    parser.add_argument("--fail-reservation", action="store_true", help="force the early capacity check to reject")
    parser.add_argument("--mode", action="append", help="run only this mode; repeat as needed")
    parser.add_argument("--buffers", type=int, default=15, help="verify actual configured buffer count (requires --rebase)")
    parser.add_argument("--files", type=int, default=20, help="FILES count for table-placement tests (8..255)")
    parser.add_argument("--fail-table-allocation", action="store_true", help="force the development UMB allocation to fail")
    parser.add_argument("--upper-access-control", action="store_true", help="require rejection of a corrupted table snapshot after EMS cleanup")
    parser.add_argument("--share", action="store_true", help="run SHARE/NLSFUNC compatibility contracts before the table probes")
    parser.add_argument("--fcb-keep", type=int, choices=(0, 1), default=0,
                        help="FCBS=4 keep count; 1 prevents SHARE replacing the boot cache")
    args = parser.parse_args()
    if args.share and not args.rebase:
        parser.error("--share requires --rebase")
    if args.fcb_keep and not args.rebase:
        parser.error("--fcb-keep requires --rebase")
    if args.fail_table_allocation and not args.rebase:
        parser.error("--fail-table-allocation requires --rebase")
    if args.upper_access_control and (not args.rebase or args.files > 20 or args.fail_table_allocation
                                      or args.stale_cds_control or args.warm_reset):
        parser.error("--upper-access-control requires eligible upper tables without another control or reset")
    if not 1 <= args.buffers <= 99 or (args.buffers != 15 and not args.rebase):
        parser.error("--buffers must be 1..99 and custom counts require --rebase")
    if not 8 <= args.files <= 255 or (args.files != 20 and not args.rebase):
        parser.error("--files must be 8..255 and custom counts require --rebase")
    if args.fail_reservation and not args.early:
        parser.error("--fail-reservation requires --early")
    if (args.scan or args.rebase) and not (args.early and args.tail_body):
        parser.error("--scan/--rebase requires --early --tail-body")
    if args.compact and not args.rebase:
        parser.error("--compact requires --rebase")
    if args.warm_reset and (not args.rebase or args.scan):
        parser.error("--warm-reset requires --rebase and excludes --scan")
    if args.stale_cds_control and (not args.rebase or args.fail_reservation or args.warm_reset):
        parser.error("--stale-cds-control requires successful rebasing without reset")
    scratch = Path(tempfile.mkdtemp(prefix="bios-low-boot-", dir=ROOT / "out"))
    manifest = build(scratch, early=args.early, tail_body=args.tail_body, scan=args.scan, rebase=args.rebase, compact=args.compact,
                     reservation_limit=0x10 if args.fail_reservation else 0xfff0, fail_tables=args.fail_table_allocation)
    high_manifest = build_high(scratch / "high", scratch)
    if args.rebase:
        layout = scratch / "public-layout.bin"
        run([ROOT / "bin/jwasm-bin", f"-I{ROOT / 'src/INC'}", f"-Fo{layout}",
             ROOT / "tests/bios_public_layout_masm.asm"], ROOT)
        names = ("SYSI_DPB", "SYSI_SFT", "SYSI_CDS", "SYSI_NUMIO", "SYSI_NCDS", "SYSI_DEV",
                 "DPB_NEXT_DPB", "DPB_DRIVER_ADDR", "DPB_SECTOR_SIZE", "CURDIR_DEVPTR", "CURDIRLEN",
                 "SFLINK", "SFCOUNT", "SFTABLE", "SF_ENTRY_SIZE", "SF_REF_COUNT", "SF_DEVPTR", "SF_NAME",
                 "SDEVNEXT", "SDEVATT", "SDEVNAME", "SYSI_CON",
                 "SYSI_BUF", "HASH_PTR", "HASH_COUNT", "BUFFER_BUCKET", "HASH_ENTRY_SIZE", "BUF_NEXT", "SYSI_FCB")
        values = struct.unpack(f"<{len(names)}H", layout.read_bytes())
        (scratch / "public-layout.inc").write_text("".join(
            f"PUB_{name} equ {value}\n" for name, value in zip(names, values)))
        run(["nasm", "-f", "bin", "-DNO_DEBUG_EXIT", *(["-DREQUIRE_SHARE"] if args.share else []), ROOT / "tests/int21_fcb_probe.asm",
             "-o", scratch / "I21FCB.COM"], ROOT)
        if args.share:
            run(["nasm", "-f", "bin", "-DNO_DEBUG_EXIT", ROOT / "tests/int21_compat_probe.asm",
                 "-o", scratch / "I21COMP.COM"], ROOT)
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
        variants = {name: (high, config + f"LASTDRIVE=Z\r\nFILES={args.files}\r\nFCBS=4,{args.fcb_keep}\r\nBUFFERS={args.buffers}\r\n")
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
            options.append(f"-DEXPECT_BUFFERS={args.buffers}")
            fields = dict(zip(names, values))
            sft_paras = ((args.files - 5) * fields['SF_ENTRY_SIZE'] + fields['SFTABLE'] + 15) // 16 + 1
            fcb_paras = (4 * fields['SF_ENTRY_SIZE'] + fields['SFTABLE'] + 15) // 16 + 1
            options.append(f"-DEXPECT_TABLES_UPPER={int(name == 'emm-high' and sft_paras + fcb_paras <= 74 and not args.fail_table_allocation)}")
            options.append(f"-DEXPECT_TABLE_PARAS={sft_paras + fcb_paras}")
            options.append(f"-DEXPECT_FCB_DELTA={sft_paras + 1}")
            options.append(f"-DEXPECT_EXTRA_SFT={args.files - 5}")
            if args.share and args.fcb_keep == 0:
                options.append("-DEXPECT_FCB_REPLACED")
        if args.compact:
            options.append("-DEXPECT_COMPACT")
        if args.warm_reset:
            options.append("-DWARM_RESET")
        upper_control = args.upper_access_control and name == "emm-high"
        negative = name == "live-stale-entry" or (args.stale_cds_control and high) or upper_control
        if upper_control:
            options.append("-DUPPER_ACCESS_CONTROL")
        if name == "live-stale-entry":
            options.append("-DOMIT_LIVE_PUBLICATION")
        if args.stale_cds_control and high:
            options.append("-DSTALE_CDS_CONTROL")
        run(["nasm", "-f", "bin", f"-I{scratch}/", f"-I{ROOT / 'tests'}/",
             f"-DEXPECT_HIGH={int(high)}",
             f"-DEXPECT_ACTIVE={int(args.early and high and not args.fail_reservation)}", *options,
             ROOT / "tests/bios_low_boot_probe.asm", "-o", probe], ROOT)
        image = scratch / f"{name}.img"
        shutil.copyfile(ROOT / "out/floppy.img", image)
        for source, destination in ((scratch / "IO.SYS", "IO.SYS"), (probe, "LOWBOOT.COM")):
            subprocess.run(["mcopy", "-o", "-i", str(image), str(source), f"::{destination}"],
                           env=env, check=True)
        if args.rebase:
            run(["nasm", "-f", "bin", "-DNO_DEBUG_EXIT", *(["-DEXPECT_UMB"] if name == "emm-high" else []),
                 ROOT / "tests/int21_system_probe.asm", "-o", scratch / "I21SYS.COM"], ROOT)
            for test_name in ("I21FCB.COM", "I21SYS.COM") + (("I21COMP.COM",) if args.share else ()):
                subprocess.run(["mcopy", "-o", "-i", str(image), str(scratch / test_name), f"::{test_name}"],
                               env=env, check=True)
        for destination, text in (("CONFIG.SYS", config), ("AUTOEXEC.BAT",
                                  "@ECHO OFF\r\nCTTY AUX\r\n"
                                  + ("SHARE.EXE /F:4096 /L:40\r\nI21FCB.COM\r\nNLSFUNC.EXE\r\nI21COMP.COM\r\n" if args.share else "")
                                  + ("I21SYS.COM\r\nI21FCB.COM\r\n" if args.rebase else "") + "LOWBOOT.COM\r\n")):
            subprocess.run(["mcopy", "-o", "-i", str(image), "-", f"::{destination}"],
                           input=text.encode(), env=env, check=True)
        log = scratch / f"{name}.log"
        with log.open("wb") as stream:
            debug_options = (["-debugcon", f"file:{scratch / (name + '.scan')}",
                              "-global", "isa-debugcon.iobase=0xe9"] if args.scan else [])
            try:
                command = ["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
                                "-display", "none", "-monitor", "none", "-serial", "stdio",
                                "-boot", "a", "-no-reboot", *debug_options, "-device",
                                "isa-debug-exit,iobase=0xf4,iosize=0x04", "-drive",
                                f"if=floppy,index=0,format=raw,file={image},cache=writethrough"]
                if args.warm_reset:
                    command.remove("-no-reboot")
                    run_warm_reset(command, log, stream, scratch / f"{name}.qmp")
                else:
                    subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=35)
            except subprocess.TimeoutExpired:
                pass
        result = log.read_bytes()
        passed = b"BIOS_LOW_BOOT_PASS" in result
        if args.warm_reset and result.count(b"BIOS_WARM_RESET_READY") != 1:
            raise RuntimeError(f"reset marker count was not exactly one: {log}")
        if args.stale_cds_control and high:
            if b"BIOS_PUBLIC_CONTROL_READY" not in result or b"BIOS_LOW_BOOT_FAIL" not in result:
                raise RuntimeError(f"stale CDS control did not reach explicit rejection: {log}")
        if upper_control:
            for marker in (b"BIOS_UPPER_CONTROL_READY", b"BIOS_UPPER_CONTROL_CLEAN", b"BIOS_LOW_BOOT_FAIL"):
                if marker not in result:
                    raise RuntimeError(f"upper-table control missed {marker!r}: {log}")
        if (passed == negative or (passed and b"BIOS_LOW_BOOT_FAIL" in result)
                or (name.startswith("live-") and b"BIOS_LIVE_READY" not in result)):
            raise RuntimeError(f"FAIL {name}: {log}\n{result.decode(errors='replace')}")
        if args.rebase and (b"INT21_FCB_PASS" not in result or b"INT21_SYSTEM_PASS" not in result
                            or re.search(rb"INT21_[^\r\n]*FAIL", result)):
            raise RuntimeError(f"FCB/system regression with relocated tables: {log}")
        if args.share and b"INT21_COMPAT_PASS" not in result:
            raise RuntimeError(f"SHARE/NLSFUNC compatibility did not pass: {log}")
        if args.share and result.count(b"INT21_FCB_PASS") != 2:
            raise RuntimeError(f"FCB contracts must pass both before and after compatibility probes: {log}")
        if args.rebase and not negative:
            if name == "emm-high" and sft_paras + fcb_paras <= 74 and not args.fail_table_allocation:
                if b"BIOS_UPPER_ACCESS_PASS" not in result:
                    raise RuntimeError(f"upper-table accessibility was not checked: {log}")
            placement = None
            if not high:
                placement = "LOW"
            elif args.buffers in (1, 15, 39):
                placement = "HIGH"
            elif args.buffers == 99 or (args.buffers == 40 and not args.fail_reservation):
                placement = "MIXED"
            if placement and f"BIOS_BUFFERS_COUNT_OK {placement}".encode() not in result:
                raise RuntimeError(f"wrong buffer placement, expected {placement}: {log}")
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
