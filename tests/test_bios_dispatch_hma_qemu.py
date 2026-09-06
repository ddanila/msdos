#!/usr/bin/env python3
"""Boot the shared BIOS decoder in HMA behind its real low A20 tail gate."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path,
                        default=Path(os.environ.get("FLOPPY_IMAGE", ROOT / "out/floppy.img")))
    parser.add_argument("--omit-a20-restore", action="store_true",
                        help="negative control: bypass the low E705h restoration")
    parser.add_argument("--high-tables", action="store_true",
                        help="copy the complete command tables high and poison the low originals")
    parser.add_argument("--stale-table", action="store_true",
                        help="negative control: omit the post-publication table update")
    args = parser.parse_args()
    subprocess.run(["make", "dos", "bios", str(ROOT / "src/DEV/HIMEM/HIMEM.SYS")],
                   cwd=ROOT, check=True)
    work = Path(tempfile.mkdtemp(prefix="bios-dispatch-hma-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    flags = f"-I{ROOT / 'src/BIOS'} -DSEPARATE_TEST -DHMA_TEST"
    if args.omit_a20_restore:
        flags += " -DOMIT_A20_RESTORE"
    if args.high_tables:
        flags += " -DHIGH_TABLES_TEST"
    if args.stale_table:
        flags += " -DSTALE_TABLE"
    assembled = subprocess.run([str(ROOT / "bin/jwasm-masm"), flags,
                                f"{ROOT / 'tests/bios_dispatch_masm.asm'},{work / 'probe.obj'};"],
                               capture_output=True)
    (work / "assemble.log").write_bytes(assembled.stdout + assembled.stderr)
    if assembled.returncode:
        raise ValueError(f"decoder assembly failed: {work / 'assemble.log'}")
    linker = runpy.run_path(str(ROOT / "bin/wlink"))["wlink_bin"]()
    subprocess.run([linker, "format", "dos", "option", "quiet",
                    "option", "packcode=1", "option", "packdata=1",
                    "option", "nofarcalls", "option", "map=probe.map",
                    "name", "probe.exe", "file", "probe.obj"], cwd=work, check=True)
    image = work / "boot.img"
    shutil.copyfile(args.image, image)
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    for source, target in ((ROOT / "src/BIOS/IO.SYS", "IO.SYS"),
                           (ROOT / "src/DOS/MSDOS.SYS", "MSDOS.SYS"),
                           (ROOT / "src/DEV/HIMEM/HIMEM.SYS", "HIMEM.SYS"),
                           (work / "probe.exe", "DISPATCH.EXE")):
        subprocess.run(["mcopy", "-o", "-i", str(image), str(source), "::" + target],
                       env=env, check=True)
    for name, data in (("CONFIG.SYS", "DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\nDOS=HIGH\r\n"),
                       ("AUTOEXEC.BAT", "@ECHO OFF\r\nDISPATCH.EXE\r\n")):
        (work / name).write_bytes(data.encode("ascii"))
        subprocess.run(["mcopy", "-o", "-i", str(image), str(work / name), "::" + name],
                       env=env, check=True)
    debug = work / "debug.bin"
    command = ["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
               "-display", "none", "-monitor", "none", "-serial", "none",
               "-drive", f"if=floppy,format=raw,file={image}", "-boot", "a", "-no-reboot",
               "-debugcon", f"file:{debug}", "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
    timed_out = False
    try:
        result = subprocess.run(command, capture_output=True, timeout=20)
        code, output = result.returncode, result.stdout + result.stderr
    except subprocess.TimeoutExpired as error:
        timed_out = True
        code, output = None, (error.stdout or b"") + (error.stderr or b"")
    (work / "qemu.log").write_bytes(output)
    trace = debug.read_bytes() if debug.exists() else b""
    inputs = [args.image, ROOT / "src/BIOS/IO.SYS", ROOT / "src/DOS/MSDOS.SYS",
              ROOT / "src/DEV/HIMEM/HIMEM.SYS", ROOT / "src/BIOS/DISPATCH.INC",
              ROOT / "src/BIOS/MSBSEG.INC", ROOT / "src/BIOS/HIGHROM.INC",
              ROOT / "src/BIOS/COMPLETE.INC",
              ROOT / "src/BIOS/DEVTABLE.INC",
              ROOT / "tests/bios_dispatch_masm.asm", Path(__file__),
              work / "probe.exe", image, work / "CONFIG.SYS", work / "AUTOEXEC.BAT"]
    passed = code == 33 and trace == b"BP"
    report = dict(passed=passed, exit_code=code, timed_out=timed_out,
                  trace_hex=trace.hex(), omit_a20_restore=args.omit_a20_restore,
                  high_tables=args.high_tables,
                  stale_table=args.stale_table,
                  cpu="486", ram_mib=8,
                  emulator=subprocess.check_output(["qemu-system-i386", "--version"], text=True).splitlines()[0],
                  inputs={str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})
    (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    if not passed:
        raise ValueError(f"HMA decoder failed: exit={code}, trace={trace!r}, timeout={timed_out}")
    print("PASS: HMA decoder, poisoned staging copy, A20-off entry and complete device frames")


if __name__ == "__main__":
    main()
