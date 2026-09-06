#!/usr/bin/env python3
"""Reject fallback to a second allocator after a present XMS provider fails."""
import argparse
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, default=ROOT / "out/floppy.img")
    parser.add_argument("--bad-fallback", action="store_true",
                        help="negative control: allow provider failures to use INT 15h")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="emm-xms-owner-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    source = (ROOT / "src/MEMM/MEMM/ALLOCMEM.ASM").read_text()
    bodies = []
    for name in ("AllocMem", "XMSAlloc"):
        matches = re.findall(rf"(?ims)^{name}\s+proc\s+near\b.*?^{name}\s+endp\b", source)
        if len(matches) != 1:
            raise ValueError(f"expected exactly one {name} procedure")
        bodies.append(matches[0])
    code = "\n".join(bodies)
    if args.bad_fallback:
        code, count = re.subn(r"(?m)^XA_reserve_fail:\s*\n\s*or\s+\[msg_flag\],MEM_ERR_MSG\s*\n\s*clc",
                              "XA_reserve_fail:\n stc", code)
        if count != 1:
            raise ValueError("negative control did not alter the failure boundary")
    # Use the production message bit definition, not a duplicated numeric value.
    constants = (ROOT / "src/MEMM/MEMM/EMM386.INC").read_text()
    definition = re.search(r"(?mi)^MEM_ERR_MSG\s+equ\s+[^;\n]+", constants).group()
    (work / "OWNER_CODE.INC").write_text(definition + "\n" + code + "\n")
    shutil.copyfile(ROOT / "tests/emm_xms_owner_masm.asm", work / "probe.asm")
    run(ROOT / "bin/jwasm-masm", "-DNOHIMEM -I.", "probe.asm,probe.obj;", cwd=work)
    run(ROOT / "bin/wlink", "probe.obj,probe.exe,probe.map;", cwd=work)
    run(ROOT / "bin/exe2bin", "probe.exe", "probe.com", cwd=work)
    run("nasm", "-f", "bin", ROOT / "tests/qemu_exit.asm", "-o", work / "qexit.com")
    image = work / "boot.img"
    shutil.copyfile(args.image, image)
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    for name in ("probe", "qexit"):
        run("mcopy", "-o", "-i", image, work / f"{name}.com", f"::{name}.com", env=env)
    for name, content in (("CONFIG.SYS", "FILES=20\r\n"),
                          ("AUTOEXEC.BAT", "@ECHO OFF\r\nPROBE.COM\r\nQEXIT.COM\r\n")):
        run("mcopy", "-o", "-i", image, "-", "::" + name, input=content.encode(), env=env)
    debug = work / "debug.bin"
    result = subprocess.run([
        "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
        "-display", "none", "-monitor", "none", "-serial", "none",
        "-drive", f"if=floppy,format=raw,file={image}", "-boot", "a", "-no-reboot",
        "-debugcon", f"file:{debug}", "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
    ], timeout=30, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (work / "qemu.log").write_bytes(result.stdout)
    if result.returncode != 33:
        raise ValueError(f"probe did not finish: QEMU exit {result.returncode}")
    records = list(struct.iter_unpack("<2s9H", debug.read_bytes()))
    # id, message, retained handle, allocation/lock/unlock/free/pool/fallback counts
    expected = [
        (0, 0, 0, 0, 0, 0, 0, 0, 1),
        (1, 0, 0x1234, 1, 1, 0, 0, 1, 0),
        (2, 4, 0, 1, 0, 0, 0, 0, 0),
        (3, 4, 0, 1, 1, 0, 1, 0, 0),
        (4, 4, 0, 1, 1, 1, 1, 0, 0),
        (5, 4, 0, 0, 0, 0, 0, 0, 0),
        (6, 4, 0, 0, 0, 0, 0, 0, 0),
    ]
    actual = [row[1:] for row in records if row[0] == b"XA"]
    if len(records) != 7 or actual != expected:
        raise ValueError(f"single-owner boundary failed: {actual!r}")
    print("PASS: absent/successful/failing XMS providers preserve the allocator boundary")


if __name__ == "__main__":
    main()
