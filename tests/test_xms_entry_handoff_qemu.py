#!/usr/bin/env python3
"""Boot DOS and exercise its full cached-XMS-entry update and legacy form."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path,
                        default=Path(os.environ.get("FLOPPY_IMAGE", ROOT / "out/floppy.img")))
    parser.add_argument("--old-kernel", type=Path,
                        help="negative control: kernel without the full-entry protocol")
    args = parser.parse_args()
    subprocess.run(["make", "dos", "bios", str(ROOT / "src/DEV/HIMEM/HIMEM.SYS")],
                   cwd=ROOT, check=True)
    work = Path(tempfile.mkdtemp(prefix="xms-entry-handoff-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    kernel = args.old_kernel or ROOT / "src/DOS/MSDOS.SYS"
    files = {"IO.SYS": ROOT / "src/BIOS/IO.SYS", "MSDOS.SYS": kernel,
             "HIMEM.SYS": ROOT / "src/DEV/HIMEM/HIMEM.SYS"}
    report = dict(passed=False, images={},
                  emulator=subprocess.check_output(["qemu-system-i386", "--version"], text=True).splitlines()[0],
                  base_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest(),
                  probe_sha256=hashlib.sha256((ROOT / "tests/xms_entry_handoff_probe.asm").read_bytes()).hexdigest(),
                  input_sha256={
        name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in files.items()})
    try:
        for mode in ("HIGH", "LOW"):
            probe = work / f"{mode}.com"
            subprocess.run(["nasm", "-f", "bin", *(["-DDOS_LOW"] if mode == "LOW" else []),
                            str(ROOT / "tests/xms_entry_handoff_probe.asm"), "-o", str(probe)], check=True)
            disk = work / f"{mode}.img"
            shutil.copyfile(args.image, disk)
            env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
            for name, path in dict(files, **{"HANDOFF.COM": probe}).items():
                subprocess.run(["mcopy", "-o", "-i", str(disk), str(path), "::" + name], env=env, check=True)
            for name, data in {"CONFIG.SYS": f"DEVICE=HIMEM.SYS /TESTMEM:OFF\r\nDOS={mode}\r\n",
                               "AUTOEXEC.BAT": "@ECHO OFF\r\nHANDOFF.COM\r\n"}.items():
                subprocess.run(["mcopy", "-o", "-i", str(disk), "-", "::" + name],
                               input=data.encode(), env=env, check=True)
            report["images"][mode] = hashlib.sha256(disk.read_bytes()).hexdigest()
            debug = work / f"{mode}.debug"
            result = subprocess.run([
                "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "16",
                "-drive", f"if=floppy,format=raw,file={disk}", "-boot", "a",
                "-display", "none", "-monitor", "none", "-serial", "none", "-no-reboot",
                "-debugcon", f"file:{debug}", "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
                capture_output=True, timeout=25)
            (work / f"{mode}.log").write_bytes(result.stdout + result.stderr)
            if result.returncode != 33 or debug.read_bytes() != b"P":
                raise RuntimeError(f"DOS={mode} entry protocol failed: {debug.read_bytes()!r}")
            print(f"PASS: DOS={mode} cached XMS entry protocol", flush=True)
        report["passed"] = True
    finally:
        (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
