#!/usr/bin/env python3
"""Persist a SETVER edit and deletion across two in-process QMP resets.

Input must already load DOS high and DEVICE=SETVER.EXE. Only a private image
copy is modified. --omit-loader is a deliberate negative control.
"""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

from capture_drdos_memory import qmp_system_reset

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--omit-loader", action="store_true")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="setver-warm-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    image, serial = work / "boot.img", work / "serial.log"
    qmp = work / "reset.qmp"
    shutil.copyfile(args.image, image)
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")

    def run(command, **kwargs):
        return subprocess.run(command, env=env, check=True, **kwargs)

    for source, name, flags in (
        ("setver_probe.asm", "SETPROBE.COM", ["-DEXPECT_HIGH=1"]),
        ("warm_reboot.asm", "WARMBOOT.COM", []),
        ("qemu_exit.asm", "QEXIT.COM", []),
    ):
        binary = work / name
        run(["nasm", "-f", "bin", *flags, ROOT / "tests" / source, "-o", binary])
        run(["mcopy", "-o", "-i", image, binary, f"::{name}"])
    config = run(["mtype", "-i", image, "::CONFIG.SYS"], capture_output=True).stdout
    if args.omit_loader:
        config = b"\r\n".join(line for line in config.splitlines()
                              if not re.search(rb"(?i)^\s*DEVICE\s*=.*SETVER\.EXE", line)) + b"\r\n"
        run(["mcopy", "-o", "-i", image, "-", "::CONFIG.SYS"], input=config)
    (work / "config.sys").write_bytes(config)
    batch = (
        "@ECHO OFF\r\n"
        "IF EXIST DELETE.OK GOTO CLEARED\r\n"
        "IF EXIST EDIT.OK GOTO LOADED\r\n"
        "SETVER SETPROBE.COM 4.20\r\n"
        "SETPROBE.COM > BEFORE.TXT\r\n"
        "ECHO READY>EDIT.OK\r\n"
        "CTTY AUX\r\nWARMBOOT.COM\r\n"
        ":LOADED\r\nSETPROBE.COM > LOADED.TXT\r\n"
        "SETVER SETPROBE.COM /DELETE /QUIET\r\n"
        "ECHO READY>DELETE.OK\r\n"
        "CTTY AUX\r\nWARMBOOT.COM\r\n"
        ":CLEARED\r\nSETPROBE.COM > CLEARED.TXT\r\nQEXIT.COM\r\n"
    ).encode("ascii")
    run(["mcopy", "-o", "-i", image, "-", "::AUTOEXEC.BAT"], input=batch)
    process = subprocess.Popen([
        "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
        "-display", "none", "-monitor", "none", "-boot", "a",
        "-drive", f"if=floppy,format=raw,file={image},cache=writethrough",
        "-qmp", f"unix:{qmp},server=on,wait=off", "-serial", f"file:{serial}",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for count in (1, 2):
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f"guest exited before reset {count}")
                if (qmp.exists() and serial.exists()
                        and serial.read_text(errors="replace").count("WARM_RESET_READY") >= count):
                    break
                time.sleep(0.1)
            else:
                raise RuntimeError(f"guest did not reach reset {count}: {serial}")
            qmp_system_reset(qmp)
        if process.wait(timeout=30) != 33:
            raise RuntimeError("guest did not exit through QEXIT")
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    owners = []
    for name, expected in (("BEFORE", "4.20"), ("LOADED", "4.20"), ("CLEARED", "6.22")):
        output = run(["mtype", "-i", image, f"::{name}.TXT"], capture_output=True).stdout.decode("ascii")
        (work / f"{name.lower()}.txt").write_text(output)
        versions = re.findall(r"SETVER_PROBE_VERSION=(\d+\.\d+)", output)
        owner = re.findall(r"SETVER_HIGH_LOW_OWNER=([0-9A-F]{4}:[0-9A-F]{4})", output)
        if versions != [expected] or len(owner) != 1 or "SETVER_OWNERSHIP_FAIL" in output:
            raise RuntimeError(f"{name}: expected high/low-owner version {expected}: {output!r}")
        owners.extend(owner)
    if len(set(owners)) != 1:
        raise RuntimeError(f"SETVER owner drift across resets: {owners}")
    print(f"PASS: edit/load/delete across two QMP resets; high kernel, low owner {owners[0]}")


if __name__ == "__main__":
    main()
