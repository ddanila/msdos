#!/usr/bin/env python3
"""Run the shared allocator in separate high protected code/data/stack owners."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import socket
import struct
import subprocess
import tempfile
import time

from capture_uma_topology import QMP
from report_himem_residency import LABEL_RE, PROCEDURE_RE

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wrong-owner", action="store_true",
                        help="negative control: select the poisoned code-owner data alias")
    parser.add_argument("--accept-invalid-owner", action="store_true",
                        help="negative control: replace state validation with unconditional success")
    parser.add_argument("--corrupt-staged-owner", action="store_true",
                        help="negative control: alter a staged handle lock count before publication")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="xms-allocator-owner-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    source = ROOT / "src/DEV/HIMEM"
    prefix = (source / "HIMEM.ASM").read_text().split("device_header:", 1)[0]
    prefix += (source / "XMSRECORD.INC").read_text()
    prefix += (source / "XMSERROR.INC").read_text()
    equates = re.findall(r"^\w+\s+equ\s+.+$", prefix, re.MULTILINE | re.IGNORECASE)
    (work / "allocator_equates.inc").write_text("\n".join(equates) + "\n")
    binary, listing = work / "service.bin", work / "service.lst"
    subprocess.run([str(ROOT / "bin/jwasm-bin"), "-q", "-bin", "-Sa",
                    *(["-DACCEPT_INVALID_OWNER"] if args.accept_invalid_owner else []),
                    *(["-DCORRUPT_STAGED_OWNER"] if args.corrupt_staged_owner else []),
                    f"-I{work}", f"-I{source}", f"-Fo{binary}", f"-Fl={listing}",
                    str(ROOT / "tests/xms_allocator_owner.asm")], check=True)
    payload = binary.read_bytes()
    sectors = (len(payload) + 511) // 512
    if not 0x1000 < len(payload) <= 17 * 512:
        raise ValueError("service fixture does not fit the first floppy track")
    boot = work / "boot.bin"
    subprocess.run(["nasm", "-f", "bin", f"-DSTAGE_BYTES={len(payload)}",
                    f"-DSTAGE_SECTORS={sectors}", *(["-DWRONG_OWNER"] if args.wrong_owner else []),
                    str(ROOT / "tests/xms_allocator_owner_boot.asm"), "-o", str(boot)], check=True)
    disk = work / "boot.img"
    disk.write_bytes((boot.read_bytes() + payload).ljust(1474560, b"\0"))
    addresses = {}
    for line in listing.read_text(encoding="latin-1").splitlines():
        match = LABEL_RE.match(line) or PROCEDURE_RE.match(line)
        if match:
            addresses[match[1]] = int(match[2], 16)
    inputs = [source / name for name in ("HIMEM.ASM", "XMSALLOC.INC", "XMSHANDLE.INC", "XMSSTATE.INC", "XMSSTAGE.INC", "XMSRECORD.INC", "XMSERROR.INC")]
    inputs += [ROOT / "tests/xms_allocator_owner.asm", ROOT / "tests/xms_allocator_owner_boot.asm"]
    report = dict(passed=False, wrong_owner=args.wrong_owner,
                  accept_invalid_owner=args.accept_invalid_owner,
                  corrupt_staged_owner=args.corrupt_staged_owner,
                  services_bytes=addresses["allocator_services_end"] - addresses["xms_query_free"],
                  helpers_bytes=addresses["allocator_helpers_end"] - addresses["validate_handle"],
                  validator_bytes=addresses["allocator_validator_end"] - addresses["xms_validate_owner"],
                  stager_bytes=addresses["allocator_stager_end"] - addresses["xms_stage_allocator"],
                  inputs={str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in inputs},
                  binary_sha256=hashlib.sha256(payload).hexdigest(),
                  emulator=subprocess.check_output(["qemu-system-i386", "--version"], text=True).splitlines()[0])
    endpoint, debug = work / "qmp", work / "debug.bin"
    process = subprocess.Popen(["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
                                "-display", "none", "-monitor", "none", "-serial", "none", "-no-reboot",
                                "-drive", f"if=floppy,format=raw,file={disk}", "-boot", "a",
                                "-qmp", f"unix:{endpoint},server=on,wait=off",
                                "-debugcon", f"file:{debug}",
                                "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 20
        while not endpoint.exists():
            if process.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("QMP startup failed")
            time.sleep(.05)
        with socket.socket(socket.AF_UNIX) as connection:
            connection.connect(str(endpoint))
            qmp = QMP(connection)
            while not debug.exists() or debug.read_bytes() != b"P":
                if process.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError("allocator owner witness failed: " + repr(debug.read_bytes() if debug.exists() else b""))
                time.sleep(.05)
            qmp.call("stop")
            registers = qmp.call("human-monitor-command", {"command-line": "info registers"})
            (work / "registers.txt").write_text(registers)
            if not int(re.search(r"CR0=([0-9a-fA-F]+)", registers)[1], 16) & 1:
                raise ValueError("allocator did not execute in protected mode")
            for name, selector, base in (("CS", 0x18, 0x200000), ("DS", 0x20, 0x210000), ("SS", 0x28, 0x220000)):
                match = re.search(rf"{name}\s*=([0-9a-fA-F]+)\s+([0-9a-fA-F]+)", registers)
                if not match or tuple(int(value, 16) for value in match.groups()) != (selector, base):
                    raise ValueError(f"{name} does not select its separate high owner")
            ram_path = work / "ram.bin"
            qmp.call("human-monitor-command", {"command-line": f'pmemsave 0 8388608 "{ram_path}"'})
            ram = ram_path.read_bytes()
            if ram[0x201000:0x201025] != bytes(37):
                raise ValueError("allocator wrote to the poisoned code-relative state")
            if ram[0x9000:0x9025] != bytes([0xa5]) * 37:
                raise ValueError("allocator reused the retired low context")
            if struct.unpack_from("<HH", ram, 0x211000) != (4, 512):
                raise ValueError("authoritative high allocator context changed")
            if any(struct.unpack_from("<H", ram, 0x211012 + index * 5)[0] for index in range(4)):
                raise ValueError("test handles were not released in the high owner")
            expected = b"".join(struct.pack("<I", offset ^ 0x13579bdf) for offset in range(0, 32768, 4))
            if ram[0x110000:0x118000] != expected or ram[0x120000:0x128000] != expected:
                raise ValueError("relocating copy did not preserve actual physical data")
            qmp.call("cont")
            qmp.call("send-key", {"keys": [{"type": "qcode", "data": "spc"}], "hold-time": 1})
            if process.wait(timeout=10) != 33:
                raise ValueError("allocator witness did not finish")
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
    print("PASS: shared allocator used separate high code/data/stack owners")


if __name__ == "__main__":
    main()
