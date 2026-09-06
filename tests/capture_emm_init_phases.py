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


def parse_trace(data):
    if len(data) != 8 * 13:
        raise ValueError("incomplete or unexpected initialization trace")
    result = []
    for index in range(8):
        tag, stage, msw, ip15, cs15, ip67, cs67 = struct.unpack_from(
            "<2sB5H", data, index * 13)
        if tag != b"IP" or stage != index + 1:
            raise ValueError("invalid initialization phase order")
        result.append(dict(stage=stage, pe=msw & 1, msw=msw,
                           int15=f"{cs15:04X}:{ip15:04X}",
                           int67=f"{cs67:04X}:{ip67:04X}"))
    return result


def check_phases(rows, mode):
    final_pe = 1 if mode in ("ON", "RAM") else 0
    if [row["pe"] for row in rows] != [0] * 5 + [1, final_pe, final_pe]:
        raise ValueError("unexpected CPU activation boundary")
    for vector in ("int15", "int67"):
        if any(row[vector] != rows[0][vector] for row in rows[:7]):
            raise ValueError("interrupt entry published before final phase")
        if rows[7][vector] == rows[0][vector]:
            raise ValueError("final interrupt entry was not published")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    args = parser.parse_args()
    capture.require_tools()
    image_hash = capture.sha256(args.image)
    work = Path(tempfile.mkdtemp(prefix="emm-init-phases-", dir=capture.ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    shutil.copytree(capture.ROOT / "src/MEMM", work / "MEMM")
    build = work / "MEMM/MEMM"
    original = capture.sha256(capture.ROOT / "src/MEMM/MEMM/EMM386.EXE")
    for define in ("", "-DEMM_INIT_PHASE_TRACE"):
        subprocess.run([str(capture.ROOT / "bin/jwasm-masm"),
                        f"-Mx -t -DI386 -DNoBugMode -DNOHIMEM {define} -I. -I..\\EMM",
                        "INIT.ASM,INIT.OBJ;"], cwd=build, check=True,
                       stdout=subprocess.DEVNULL)
        subprocess.run([str(capture.ROOT / "bin/wlink"), "/NOI /PACKDATA:1 @EMM386.LNK"],
                       cwd=build, check=True, stdout=subprocess.DEVNULL)
        if not define and capture.sha256(build / "EMM386.EXE") != original:
            raise RuntimeError("default reconstruction differs from production; rebuild memm first")
    qexit = work / "QEXIT.COM"
    subprocess.run(["nasm", "-f", "bin", str(capture.QEMU_EXIT_SOURCE),
                    "-o", str(qexit)], check=True)
    records = {}
    for mode in ("ON", "OFF", "AUTO", "RAM"):
        image = work / f"{mode}.img"
        shutil.copyfile(args.image, image)
        for source, name in ((build / "EMM386.EXE", "EMM386.EXE"),
                             (capture.ROOT / "src/DEV/HIMEM/HIMEM.SYS", "HIMEM.SYS"),
                             (qexit, "QEXIT.COM")):
            capture.install_file(image, source, name)
        config = work / f"{mode}-CONFIG.SYS"
        config.write_bytes(("DEVICE=HIMEM.SYS /TESTMEM:OFF\r\n"
                            f"DEVICE=EMM386.EXE {mode}\r\nDOS=LOW\r\n").encode())
        batch = work / "AUTOEXEC.BAT"
        batch.write_bytes(b"@ECHO OFF\r\nQEXIT.COM\r\n")
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
        records[mode] = parse_trace(trace.read_bytes())
        check_phases(records[mode], mode)
        print(mode, json.dumps(records[mode]), flush=True)
    if capture.sha256(args.image) != image_hash:
        raise RuntimeError("input image changed")
    (work / "result.json").write_text(json.dumps(dict(
        input_sha256=image_hash, normal_emm_sha256=original,
        trace_emm_sha256=capture.sha256(build / "EMM386.EXE"),
        emulator=capture.qemu_identity(), records=records), indent=2) + "\n")


if __name__ == "__main__":
    main()
