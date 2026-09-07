#!/usr/bin/env python3
"""Observe a real INT 19h second boot without patching DOS or BIOS internals."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from build_bios_low_image import ROOT
from capture_vc_memory_comparison import image_file, partition_offset
from test_dos_char_retirement_qemu import ENV, install


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--profile", choices=("existing", "bare-low", "himem-high"),
                        default="existing")
    parser.add_argument("--ctty-aux", action="store_true")
    parser.add_argument("--timeout", type=int, default=20)
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="software-reboot-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    disk = work / "boot.img"
    shutil.copyfile(args.image, disk)
    # A stale receipt could falsely turn first boot into apparent second boot.
    listing = subprocess.check_output(
        ["mdir", "-b", "-i", f"{disk}@@{partition_offset(disk)}", "::/"], env=ENV)
    if any(line.upper().endswith(b"/SWBOOT.TAG") for line in listing.splitlines()):
        raise ValueError("input contains SWBOOT.TAG; use a clean frozen image")
    original = image_file(disk, "::CONFIG.SYS")
    config = original
    if args.profile == "bare-low":
        config = b"DOS=LOW\r\nFILES=20\r\nBUFFERS=15\r\nLASTDRIVE=Z\r\nSTACKS=9,128\r\n"
    elif args.profile == "himem-high":
        config = b"\r\n".join(line for line in original.splitlines()
                                  if b"EMM386" not in line.upper()) + b"\r\n"
        assert b"DOS=HIGH" in config.upper() and b"HIMEM" in config.upper()
    install(disk, "CONFIG.SYS", config)
    autoexec = b"@ECHO OFF\r\n" + (b"CTTY AUX\r\n" if args.ctty_aux else b"")
    autoexec += b"SWBOOT.COM\r\n"
    install(disk, "AUTOEXEC.BAT", autoexec)
    probe = work / "SWBOOT.COM"
    subprocess.run(["nasm", "-f", "bin", ROOT / "tests/software_reboot_probe.asm",
                    "-o", probe], check=True)
    install(disk, "SWBOOT.COM", probe.read_bytes())
    report = dict(input_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest(),
                  profile=args.profile, ctty_aux=args.ctty_aux,
                  config=config.decode("ascii"), autoexec=autoexec.decode("ascii"),
                  probe_sha256=hashlib.sha256(probe.read_bytes()).hexdigest())
    command = ["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
               "-display", "none", "-monitor", "none", "-serial", "stdio", "-boot", "c",
               "-debugcon", f"file:{work / 'debug.log'}",
               "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
               "-drive", f"if=ide,index=0,format=raw,file={disk},cache=writethrough"]
    report["command"] = command
    report["qemu_version"] = subprocess.check_output(
        ["qemu-system-i386", "--version"], text=True).splitlines()[0]
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=args.timeout)
        code, output = result.returncode, result.stdout
    except subprocess.TimeoutExpired as error:
        code, output = None, error.stdout or b""
    (work / "serial.log").write_bytes(output)
    trace = (work / "debug.log").read_bytes()
    report.update(exit_code=code, timeout_seconds=args.timeout,
                  first_boots=trace.count(b"SOFTWARE_REBOOT_READY"),
                  second_boots=trace.count(b"SOFTWARE_REBOOT_SECOND_BOOT_PASS"),
                  failure=b"SOFTWARE_REBOOT_FAIL" in trace)
    report["passed"] = (code == 33 and report["first_boots"] == 1
                        and report["second_boots"] == 1 and not report["failure"])
    (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
