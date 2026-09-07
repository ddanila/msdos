#!/usr/bin/env python3
"""Capture conventional DOS suballocations from a private fixed-profile HDD image.

CONFIG.SYS and installed binaries are preserved. The default probe is read-only.
The explicit low-SFT poison experiment mutates only a disposable guest's RAM
and follows it with FCB I/O. Results describe the probe process, not VC.
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

from capture_vc_memory_comparison import ROOT, image_file, partition_offset
from report_dos_bios_residency import parse_map


def decode_rows(trace):
    rows = {}
    for name, count in (("MCB", 3), ("SUB", 4), ("UNCLASSIFIED", 2),
                        ("SFT", 5), ("LOWSFT", 5)):
        pattern = r"^" + name + r" " + r"([0-9A-F]{4}) " * count + r"$"
        rows[name] = [[int(field, 16) for field in match]
                      for match in re.findall(pattern, trace, re.MULTILINE)]
        if len(rows[name]) != len(re.findall(r"^" + name + r" ", trace, re.MULTILINE)):
            raise ValueError(f"malformed {name} row")
    if not rows["MCB"]:
        raise ValueError("census has no parsed MCB rows")
    if len(rows["LOWSFT"]) > 1:
        raise ValueError("multiple retained-low SFT rows")
    seen = set()
    for segment, offset, count, occupied, references in rows["SFT"] + rows["LOWSFT"]:
        # DOS=HIGH can publish an HMA SFT. Reject offset wrap, not addresses
        # above 1 MiB; do not normalize an HMA owner into a low-memory alias.
        if (segment < 0x70 or offset + 6 + count * 59 > 0x10000
                or not 1 <= count <= 255 or not 0 <= occupied <= count
                or references < occupied or bool(references) != bool(occupied)):
            raise ValueError("invalid SFT ownership row")
    for segment, offset, *_ in rows["SFT"]:
        address = segment * 16 + offset
        if address in seen:
            raise ValueError("duplicate SFT ownership row")
        seen.add(address)
    for index, (start, owner, size) in enumerate(rows["MCB"]):
        end = start + size + 1
        if start < 0x70 or start >= 0xA000 or end > 0xFFFF:
            raise ValueError("invalid conventional MCB extent")
        if index and start != sum((rows["MCB"][index-1][0], rows["MCB"][index-1][2], 1)):
            raise ValueError("noncontiguous MCB chain")
    pending = list(rows["SUB"])
    gaps = list(rows["UNCLASSIFIED"])
    for start, owner, size in rows["MCB"]:
        if owner != 8:
            continue
        cursor, end = start + 1, start + size + 1
        while pending and pending[0][0] == cursor:
            mark, kind, data, paras = pending.pop(0)
            if data != mark + 1 or data + paras > end:
                raise ValueError("suballocation exceeds its system MCB")
            cursor = data + paras
        if cursor != end:
            if not gaps or gaps.pop(0) != [cursor, end]:
                raise ValueError("unaccounted system allocation")
    if pending or gaps:
        raise ValueError("orphan suballocation or gap")
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--kernel", type=Path,
                        help="our matching kernel, required with --dos-map")
    parser.add_argument("--dos-map", type=Path,
                        help="our kernel map: also inspect its retained low SFT copy")
    parser.add_argument("--poison-low-sft", action="store_true",
                        help="invalidate our low SFT copy in the private guest, then test FCB I/O")
    args = parser.parse_args()
    if bool(args.kernel) != bool(args.dos_map):
        parser.error("--kernel and --dos-map must be supplied together")
    if args.poison_low_sft and not args.dos_map:
        parser.error("--poison-low-sft requires our matching --kernel and --dos-map")
    probe_defines = []
    if args.kernel:
        kernel = args.kernel.read_bytes()
        if kernel != image_file(args.image, "::MSDOS.SYS"):
            parser.error("kernel does not match the installed image")
        _, symbols = parse_map(args.dos_map)
        if symbols["CARPOS"] - symbols["sfTabl"] != 301:
            parser.error("unexpected initial SFT layout")
        offset = symbols["sfTabl"]
        if kernel[offset:offset + 6] != b"\xff\xff\xff\xff\x05\x00":
            parser.error("map does not identify the kernel's initial SFT header")
        probe_defines = [f"-DLOW_SFT_OFFSET={symbols['sfTabl']}"]
        if args.poison_low_sft:
            probe_defines.append("-DPOISON_LOW_SFT=1")
    work = Path(tempfile.mkdtemp(prefix="system-owners-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    image = work / "boot.img"
    shutil.copyfile(args.image, image)
    spec = f"{image}@@{partition_offset(image)}"
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")

    def run(command, **kwargs):
        return subprocess.run(command, env=env, check=True, **kwargs)

    config = image_file(image, "::CONFIG.SYS")
    (work / "config.sys").write_bytes(config)
    installed = {name: hashlib.sha256(image_file(image, "::" + name)).hexdigest()
                 for name in ("IO.SYS", "MSDOS.SYS", "COMMAND.COM",
                              "DOS/HIMEM.SYS", "DOS/EMM386.EXE")}
    programs = [("system_owner_probe.asm", "OWNERS.COM"), ("qemu_exit.asm", "QEXIT.COM")]
    if args.poison_low_sft:
        programs.append(("int21_fcb_probe.asm", "I21FCB.COM"))
    for source, name in programs:
        binary = work / name
        defines = probe_defines if name == "OWNERS.COM" else []
        run(["nasm", "-f", "bin", *defines, ROOT / "tests" / source, "-o", binary])
        run(["mcopy", "-o", "-i", spec, binary, f"::{name}"])
    after = b"C:\\I21FCB.COM\r\n" if args.poison_low_sft else b""
    run(["mcopy", "-o", "-i", spec, "-", "::AUTOEXEC.BAT"],
        input=b"@ECHO OFF\r\nCTTY AUX\r\nC:\\OWNERS.COM\r\n" + after + b"C:\\QEXIT.COM\r\n")
    with (work / "serial.log").open("wb") as output:
        result = subprocess.run([
            "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
            "-display", "none", "-monitor", "none", "-serial", "stdio",
            "-no-reboot", "-boot", "c", "-device",
            "isa-debug-exit,iobase=0xf4,iosize=0x04", "-drive",
            f"if=ide,format=raw,file={image},cache=writethrough"],
            stdout=output, stderr=subprocess.STDOUT, timeout=35)
    trace = (work / "serial.log").read_text()
    if (result.returncode != 33 or trace.count("SYSTEM_OWNER_END") != 1
            or "SYSTEM_OWNER_FAIL" in trace):
        raise RuntimeError(f"incomplete census: {work / 'serial.log'}")
    rows = decode_rows(trace)
    if not rows["SFT"]:
        raise RuntimeError("missing SFT census")
    if args.poison_low_sft and (trace.count("LOW_SFT_POISON_PASS") != 1
                               or trace.count("INT21_FCB_PASS") != 1):
        raise RuntimeError("handle/FCB I/O failed after low SFT invalidation")
    if args.dos_map:
        if len(rows["LOWSFT"]) != 1:
            raise RuntimeError("missing retained-low SFT census")
        shutil.copyfile(args.dos_map, work / "MSDOS.MAP")
    report = dict(poison_low_sft=args.poison_low_sft,
                  input_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest(),
                  config_sha256=hashlib.sha256(config).hexdigest(),
                  installed_sha256=installed,
                  emulator=subprocess.check_output(["qemu-system-i386", "--version"], text=True).splitlines()[0],
                  rows=rows)
    (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
