#!/usr/bin/env python3
"""Observe EMM initialization boundaries in a privately linked trace build."""
import argparse
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

import capture_drdos_memory as capture
from emm_loader_rebase import include as rebase_include, manifest as rebase_manifest


def parse_trace(data, *, split=False, rejected=False, activation_stack=False,
                lifecycle=False, loader=False, rebase=False):
    moved = None
    if rebase:
        if len(data) < 34:
            raise ValueError("missing prepared-image move")
        tag, old, new, paragraphs = struct.unpack_from("<2s3H", data, 26)
        if tag != b"RB" or new != old + 32 or paragraphs <= 32:
            raise ValueError("invalid prepared-image move")
        moved = dict(old=old, new=new, paragraphs=paragraphs)
        data = data[:26] + data[34:]
    order = ([1, 9, 10] if rejected else
             [1, 9, *range(2, 9)] if split else list(range(1, 9)))
    if activation_stack:
        order = order[:2] + [12] + order[2:] + [13]
    if lifecycle:
        order.append(15)
    if loader:
        if not data.endswith(b"LD"):
            raise ValueError("missing SYSINIT callback completion")
        data = data[:-2]
        order.insert(2, 17)
    if len(data) != len(order) * 13:
        raise ValueError("incomplete or unexpected initialization trace")
    result = []
    for index, expected in enumerate(order):
        tag, stage, msw, ip15, cs15, ip67, cs67 = struct.unpack_from(
            "<2sB5H", data, index * 13)
        if tag != b"IP" or stage != expected:
            raise ValueError("invalid initialization phase order")
        result.append(dict(stage=stage, pe=msw & 1, msw=msw,
                           int15=f"{cs15:04X}:{ip15:04X}",
                           int67=f"{cs67:04X}:{ip67:04X}"))
    if moved:
        result[2]["move"] = moved
    return result


def check_phases(rows, mode, *, split=False, rejected=False, activation_stack=False,
                 lifecycle=False, loader=False, rebase=False):
    if rebase and not rejected:
        for vector in ("int15", "int67"):
            if int(rows[-1][vector].split(":")[0], 16) != rows[2]["move"]["new"]:
                raise ValueError("activated entry does not follow the moved image")
    if loader:
        if any(rows[2][key] != rows[1][key] for key in ("pe", "int15", "int67")):
            raise ValueError("loader resume changed prepared machine state")
        rows = rows[:2] + rows[3:]
    if lifecycle:
        if any(rows[-1][key] != rows[-2][key] for key in ("pe", "int15", "int67")):
            raise ValueError("rejected lifecycle calls changed terminal machine state")
        rows = rows[:-1]
    if activation_stack:
        for first, second in ((rows[1], rows[2]), (rows[-2], rows[-1])):
            if any(first[key] != second[key] for key in ("pe", "int15", "int67")):
                raise ValueError("activation stack boundary changed machine state")
        rows = rows[:2] + rows[3:-1]
    if split or rejected:
        if rows[1]["pe"] or any(rows[1][key] != rows[0][key]
                                for key in ("int15", "int67")):
            raise ValueError("preparation changed CPU or public vectors")
        if rejected:
            if rows[2]["pe"] or any(rows[2][key] != rows[0][key]
                                    for key in ("int15", "int67")):
                raise ValueError("rejected preparation did not restore state")
            return
        rows = rows[:1] + rows[2:]
    final_pe = 1 if mode in ("ON", "RAM") else 0
    if [row["pe"] for row in rows] != [0] * 5 + [1, final_pe, final_pe]:
        raise ValueError("unexpected CPU activation boundary")
    for vector in ("int15", "int67"):
        if any(row[vector] != rows[0][vector] for row in rows[:7]):
            raise ValueError("interrupt entry published before final phase")
        if rows[7][vector] == rows[0][vector]:
            raise ValueError("final interrupt entry was not published")


def build_loader(work, *, rejected=False, bad_version=False, rebase=False, bad_rebase=False):
    """Private normal-layout BIOS; only SYSCONF opts into the boot handshake."""
    bios = work / "BIOS"
    shutil.copytree(capture.ROOT / "src/BIOS", bios)
    original = capture.sha256(capture.ROOT / "src/BIOS/IO.SYS")
    options = "-DBIOS_DEFER_PROVIDER"
    if rebase:
        options += " -DPROVIDER_REBASE"
        (bios / "PROVIDERFIXUPS.INC").write_text(rebase_include(
            (work / "MEMM/MEMM/EMM386.EXE").read_bytes(), bad_control=bad_rebase))
    if rejected:
        options += " -DBIOS_PROVIDER_CANCEL"
    if bad_version:
        options += " -DBIOS_PROVIDER_BAD_VERSION"
    for defines in ("", options):
        subprocess.run([str(capture.ROOT / "bin/jwasm-masm"),
                        f"-I. -I../INC {defines}", "SYSCONF.ASM,SYSCONF.OBJ;"],
                       cwd=bios, check=True, stdout=subprocess.DEVNULL)
        subprocess.run([str(capture.ROOT / "bin/wlink"), "@MSBIO.LNK"],
                       cwd=bios, check=True, stdout=subprocess.DEVNULL)
        subprocess.run([str(capture.ROOT / "bin/exe2bin"), "MSBIO.EXE", "MSBIO.BIN"],
                       cwd=bios, input=b"70\n", check=True, stdout=subprocess.DEVNULL)
        (bios / "IO.SYS").write_bytes((bios / "MSLOAD.COM").read_bytes()
                                     + (bios / "MSBIO.BIN").read_bytes())
        if not defines and capture.sha256(bios / "IO.SYS") != original:
            raise RuntimeError("normal BIOS reconstruction differs; rebuild bios first")
    return bios / "IO.SYS", original


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--split-prepare", action="store_true")
    parser.add_argument("--loader", action="store_true",
                        help="return from INIT and resume through a private SYSINIT callback")
    parser.add_argument("--loader-rebase", action="store_true",
                        help="move the prepared image upward 512 bytes and poison its old entry area")
    parser.add_argument("--loader-bad-rebase", action="store_true",
                        help="corrupt a pinned fixup precondition; require rejection, not movement")
    parser.add_argument("--loader-bad-version", action="store_true",
                        help="advertise an unsupported version; require synchronous fallback")
    parser.add_argument("--lifecycle", action="store_true",
                        help="exercise invalid calls before prepare, after prepare and after completion")
    parser.add_argument("--bad-lifecycle-control", action="store_true",
                        help="invalidate the lifecycle witness; this run must fail")
    parser.add_argument("--activation-stack", action="store_true",
                        help="resume on a separate guarded stack with BP cleared")
    parser.add_argument("--bad-stack-control", action="store_true",
                        help="invalidate the stack guard; this run must fail")
    parser.add_argument("--poison-request", action="store_true",
                        help="erase saved INIT request registers during activation")
    parser.add_argument("--reject-prepared", action="store_true")
    parser.add_argument("--bad-pool-control", action="store_true",
                        help="corrupt the cleanup witness; this run must fail")
    args = parser.parse_args()
    if args.loader_bad_rebase:
        args.loader_rebase = True
        args.reject_prepared = True
    if args.loader_rebase:
        args.loader = True
        if args.loader_bad_version:
            parser.error("rebase and version-fallback controls are separate")
    if args.loader_bad_version:
        args.loader = True
    if args.loader:
        args.split_prepare = True
        if any((args.lifecycle, args.bad_lifecycle_control, args.activation_stack,
                args.bad_stack_control, args.poison_request, args.bad_pool_control)):
            parser.error("--loader uses SYSINIT's stack; do not combine adapter-only witnesses")
        if args.loader_bad_version and args.reject_prepared:
            parser.error("version fallback control requires the normal activation path")
    if args.bad_lifecycle_control:
        args.lifecycle = True
    if args.lifecycle:
        args.split_prepare = True
    if args.bad_pool_control:
        args.reject_prepared = True
    if args.reject_prepared:
        args.split_prepare = True
    if args.poison_request:
        args.split_prepare = True
    if args.bad_stack_control:
        args.activation_stack = True
    if args.activation_stack:
        args.split_prepare = True
    capture.require_tools()
    image_hash = capture.sha256(args.image)
    work = Path(tempfile.mkdtemp(prefix="emm-init-phases-", dir=capture.ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    shutil.copytree(capture.ROOT / "src/MEMM", work / "MEMM")
    if args.loader:
        shutil.copytree(capture.ROOT / "src/INC", work / "INC")
    build = work / "MEMM/MEMM"
    original = capture.sha256(capture.ROOT / "src/MEMM/MEMM/EMM386.EXE")
    trace_defines = "-DEMM_INIT_PHASE_TRACE"
    if args.split_prepare:
        trace_defines += " -DEMM_SPLIT_PREPARE"
    if args.loader:
        trace_defines += " -DEMM_DEFER_PROVIDER"
    if args.loader_rebase:
        trace_defines += " -DPROVIDER_REBASE"
    if args.lifecycle:
        trace_defines += " -DEMM_PROVIDER_LIFECYCLE"
    if args.bad_lifecycle_control:
        trace_defines += " -DEMM_PROVIDER_BAD_LIFECYCLE"
    if args.poison_request:
        trace_defines += " -DEMM_POISON_INIT_REQUEST"
    if args.activation_stack:
        trace_defines += " -DEMM_ACTIVATION_STACK"
    if args.bad_stack_control:
        trace_defines += " -DEMM_ACTIVATION_BAD_STACK"
    if args.reject_prepared:
        trace_defines += " -DEMM_REJECT_PREPARED"
    if args.bad_pool_control:
        trace_defines += " -DEMM_PREPARE_BAD_POOL"
    for define in ("", trace_defines):
        subprocess.run([str(capture.ROOT / "bin/jwasm-masm"),
                        f"-Mx -t -DI386 -DNoBugMode -DNOHIMEM {define} -I. -I..\\EMM",
                        "INIT.ASM,INIT.OBJ;"], cwd=build, check=True,
                       stdout=subprocess.DEVNULL)
        subprocess.run([str(capture.ROOT / "bin/wlink"), "/NOI /PACKDATA:1 @EMM386.LNK"],
                       cwd=build, check=True, stdout=subprocess.DEVNULL)
        if not define and capture.sha256(build / "EMM386.EXE") != original:
            raise RuntimeError("default reconstruction differs from production; rebuild memm first")
    qexit = work / "QEXIT.COM"
    loader_image = None
    loader_hash = None
    if args.loader:
        loader_image, loader_hash = build_loader(
            work, rejected=args.reject_prepared, bad_version=args.loader_bad_version,
            rebase=args.loader_rebase, bad_rebase=args.loader_bad_rebase)
    subprocess.run(["nasm", "-f", "bin", str(capture.QEMU_EXIT_SOURCE),
                    "-o", str(qexit)], check=True)
    owner_probe = work / "OWNER.COM"
    if args.loader:
        subprocess.run(["nasm", "-f", "bin", str(capture.ROOT / "tests/emm_provider_owner_probe.asm"),
                        "-o", str(owner_probe)], check=True)
    records = {}
    owner_counts = {}
    for mode in ("ON", "OFF", "AUTO", "RAM"):
        image = work / f"{mode}.img"
        shutil.copyfile(args.image, image)
        if loader_image:
            capture.install_file(image, loader_image, "IO.SYS")
            capture.install_file(image, owner_probe, "OWNER.COM")
        for source, name in ((build / "EMM386.EXE", "EMM386.EXE"),
                             (capture.ROOT / "src/DEV/HIMEM/HIMEM.SYS", "HIMEM.SYS"),
                             (qexit, "QEXIT.COM")):
            capture.install_file(image, source, name)
        config = work / f"{mode}-CONFIG.SYS"
        config.write_bytes(("DEVICE=HIMEM.SYS /TESTMEM:OFF\r\n"
                            f"DEVICE=EMM386.EXE {mode}\r\nDOS=LOW\r\n").encode())
        batch = work / "AUTOEXEC.BAT"
        batch.write_bytes(b"@ECHO OFF\r\n" + (b"OWNER.COM\r\n" if args.loader else b"")
                          + b"QEXIT.COM\r\n")
        capture.install_file(image, config, "CONFIG.SYS")
        capture.install_file(image, batch, "AUTOEXEC.BAT")
        trace = work / f"{mode}.bin"
        with (work / f"{mode}.log").open("wb") as log:
            process = subprocess.run([
                "qemu-system-i386", *capture.hardware_args(), "-display", "none",
                "-monitor", "none", "-serial", "stdio", "-no-reboot", "-boot", "a",
                "-drive", f"if=floppy,format=raw,file={image}",
                "-debugcon", f"file:{trace}", "-global", "isa-debugcon.iobase=0xe9",
                "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
                stdout=log, stderr=subprocess.STDOUT, timeout=35)
        if process.returncode != 33:
            raise RuntimeError(f"guest did not finish {mode}: {process.returncode}")
        trace_data = trace.read_bytes()
        if args.loader:
            expected = 0 if args.reject_prepared else 1
            if not trace_data.endswith(b"DO" + struct.pack("<H", expected)):
                raise ValueError("unexpected installed EMM device owner count")
            owner_counts[mode] = expected
            trace_data = trace_data[:-4]
        records[mode] = parse_trace(trace_data, split=args.split_prepare,
                                   rejected=args.reject_prepared,
                                   activation_stack=args.activation_stack,
                                   lifecycle=args.lifecycle,
                                   loader=args.loader and not args.loader_bad_version,
                                   rebase=args.loader_rebase)
        check_phases(records[mode], mode, split=args.split_prepare,
                     rejected=args.reject_prepared, activation_stack=args.activation_stack,
                     lifecycle=args.lifecycle,
                     loader=args.loader and not args.loader_bad_version,
                     rebase=args.loader_rebase)
        print(mode, json.dumps(records[mode]), flush=True)
    if capture.sha256(args.image) != image_hash:
        raise RuntimeError("input image changed")
    (work / "result.json").write_text(json.dumps(dict(
        input_sha256=image_hash, normal_emm_sha256=original,
        trace_emm_sha256=capture.sha256(build / "EMM386.EXE"),
        split_prepare=args.split_prepare, rejected=args.reject_prepared,
        poison_request=args.poison_request,
        activation_stack=args.activation_stack,
        lifecycle=args.lifecycle,
        loader=args.loader, loader_bad_version=args.loader_bad_version,
        loader_rebase=args.loader_rebase,
        installed_owner_counts=owner_counts,
        rebase_manifest=rebase_manifest((build / "EMM386.EXE").read_bytes())
            if args.loader_rebase else None,
        normal_bios_sha256=loader_hash,
        loader_bios_sha256=capture.sha256(loader_image) if loader_image else None,
        emulator=capture.qemu_identity(), records=records), indent=2) + "\n")


if __name__ == "__main__":
    main()
