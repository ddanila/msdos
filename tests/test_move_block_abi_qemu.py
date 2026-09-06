#!/usr/bin/env python3
"""Exercise actual Move_Block frame adapter and return code, not the copier."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, default=ROOT / "out/floppy.img")
    parser.add_argument("--bad-client-frame", action="store_true")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="move-block-abi-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    source = (ROOT / "src/MEMM/MEMM/MOVEB.ASM").read_text()
    bodies = []
    for name in ("Move_Block", "MB_Exit"):
        matches = re.findall(rf"(?ims)^{name}\s+proc\s+near\b.*?^{name}\s+endp\b", source)
        if len(matches) != 1:
            raise ValueError(f"expected one {name} procedure")
        bodies.append(matches[0])
    code = "\n".join(bodies)
    if args.bad_client_frame:
        code, count = re.subn(r"(?im)^(MB_leave:)",
                             r"\1\n or word ptr [bp],FLAGS_ZF", code)
        if count != 1:
            raise ValueError("negative control did not alter the epilogue")
    (work / "COPY_ABI.INC").write_text(code + "\n")
    shutil.copyfile(ROOT / "tests/move_block_abi_masm.asm", work / "probe.asm")

    def run(*cmd, **kwargs):
        return subprocess.run([str(arg) for arg in cmd], check=True, **kwargs)

    run(ROOT / "bin/jwasm-masm", "-I.", "probe.asm,probe.obj;", cwd=work)
    run(ROOT / "bin/wlink", "probe.obj,probe.exe,probe.map;", cwd=work)
    run(ROOT / "bin/exe2bin", "probe.exe", "probe.com", cwd=work)
    image = work / "boot.img"
    shutil.copyfile(args.image, image)
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    run("mcopy", "-o", "-i", image, work / "probe.com", "::PROBE.COM", env=env)
    for name, data in (("CONFIG.SYS", "FILES=20\r\n"),
                       ("AUTOEXEC.BAT", "@ECHO OFF\r\nPROBE.COM\r\n")):
        run("mcopy", "-o", "-i", image, "-", "::" + name, input=data.encode(), env=env)
    debug = work / "debug.bin"
    result = subprocess.run([
        "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
        "-display", "none", "-monitor", "none", "-serial", "none",
        "-drive", f"if=floppy,format=raw,file={image}", "-boot", "a", "-no-reboot",
        "-debugcon", f"file:{debug}", "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
    ], timeout=30, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (work / "qemu.log").write_bytes(result.stdout)
    if result.returncode != 33 or debug.read_bytes() != b"BC":
        raise ValueError(f"copy ABI failed: exit={result.returncode}, trace={debug.read_bytes()!r}")
    print("PASS: statuses 0..3, virtual-frame adapter and acquired/unacquired parity cleanup")


if __name__ == "__main__":
    main()
