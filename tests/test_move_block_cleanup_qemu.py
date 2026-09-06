#!/usr/bin/env python3
"""Observe the installed EMM protected NMI descriptor across INT 15h copies."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import socket
import struct
import subprocess
import tempfile
import time

from capture_uma_topology import QMP

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, default=ROOT / "out/floppy.img")
    parser.add_argument("--emm386", type=Path, default=ROOT / "src/MEMM/MEMM/EMM386.EXE")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="move-block-cleanup-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    image = work / "boot.img"
    shutil.copyfile(args.image, image)
    probe = work / "probe.com"
    subprocess.run(["nasm", "-f", "bin", str(ROOT / "tests/move_block_cleanup_probe.asm"),
                    "-o", str(probe)], check=True)
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    def install(source, target, data=None):
        subprocess.run(["mcopy", "-o", "-i", str(image), str(source), "::" + target],
                       input=data, env=env, check=True)
    install(probe, "PROBE.COM")
    install(args.emm386, "EMM386.EXE")
    install(ROOT / "src/DEV/HIMEM/HIMEM.SYS", "HIMEM.SYS")
    install("-", "CONFIG.SYS", b"DEVICE=HIMEM.SYS /TESTMEM:OFF\r\nDEVICE=EMM386.EXE 1024 ON M5\r\n")
    install("-", "AUTOEXEC.BAT", b"@ECHO OFF\r\nPROBE.COM\r\n")
    endpoint, debug = work / "qmp", work / "debug.bin"
    process = subprocess.Popen([
        "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
        "-display", "none", "-monitor", "none", "-serial", "none",
        "-drive", f"if=floppy,format=raw,file={image}", "-boot", "a", "-no-reboot",
        "-qmp", f"unix:{endpoint},server=on,wait=off", "-debugcon", f"file:{debug}",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
    ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    rows = []
    report = dict(passed=False, checkpoints=rows, inputs={
        str(path): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in (args.image, args.emm386, ROOT / "src/DEV/HIMEM/HIMEM.SYS", probe)},
        emulator=subprocess.check_output(["qemu-system-i386", "--version"], text=True).splitlines()[0])
    try:
        deadline = time.monotonic() + 30
        while not endpoint.exists():
            if process.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("QMP startup failed")
            time.sleep(.05)
        with socket.socket(socket.AF_UNIX) as connection:
            connection.connect(str(endpoint))
            qmp = QMP(connection)
            for index, phase in enumerate("ABCDEF"):
                deadline = time.monotonic() + 30
                expected = b"ABCDEF"[:index + 1]
                while True:
                    trace = debug.read_bytes() if debug.exists() else b""
                    if trace == expected:
                        break
                    if not expected.startswith(trace) or process.poll() is not None:
                        raise ValueError(f"unexpected guest trace {trace!r}")
                    if time.monotonic() > deadline:
                        raise TimeoutError(f"missing phase {phase}: {trace!r}")
                    time.sleep(.05)
                qmp.call("stop")
                regs = qmp.call("human-monitor-command", {"command-line": "info registers"})
                (work / f"{phase}-registers.txt").write_text(regs)
                dump = work / f"{phase}-ram.bin"
                qmp.call("human-monitor-command", {"command-line": f'pmemsave 0 8388608 "{dump}"'})
                ram = dump.read_bytes()
                cr0 = int(re.search(r"CR0=([0-9a-fA-F]+)", regs)[1], 16)
                cr3 = int(re.search(r"CR3=([0-9a-fA-F]+)", regs)[1], 16)
                idt = int(re.search(r"IDT=\s*([0-9a-fA-F]+)", regs)[1], 16)
                if cr0 & 0x80000001 != 0x80000001:
                    raise ValueError("copy fixture is not running under protected paging")
                def physical(linear):
                    pde = struct.unpack_from("<I", ram, (cr3 & ~4095) + (linear >> 22) * 4)[0]
                    if not pde & 1 or pde & 128:
                        raise ValueError("expected a present 4-KiB page table")
                    pte = struct.unpack_from("<I", ram, (pde & ~4095) + ((linear >> 12) & 1023) * 4)[0]
                    if not pte & 1:
                        raise ValueError("IDT page is absent")
                    return (pte & ~4095) + (linear & 4095)
                descriptor = bytes(ram[physical(idt + 16 + n)] for n in range(8))
                rows.append(dict(phase=phase, idt=idt, nmi=descriptor.hex()))
                (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
                if not descriptor[5] & 128 or descriptor.hex() != rows[0]["nmi"]:
                    raise ValueError(f"NMI ownership changed at phase {phase}: {rows}")
                qmp.call("cont")
                qmp.call("send-key", {"keys": [{"type": "qcode", "data": "spc"}], "hold-time": 1})
            if process.wait(timeout=10) != 33:
                raise ValueError("guest did not finish successfully")
            report["passed"] = True
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        (work / "qemu.log").write_bytes(process.stderr.read())
        (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print("PASS: count/source/destination rejection and successful copy preserve NMI ownership")


if __name__ == "__main__":
    main()
