#!/usr/bin/env python3
"""Read QEMU UMA topology and option-ROM headers; never authorize a UMB mapping."""

import argparse
import hashlib
import json
from pathlib import Path
import select
import socket
import subprocess
import tempfile
import time

BASE, END = 0xC0000, 0xF0000


def rom_inventory(data):
    if len(data) != END - BASE:
        raise ValueError("expected the complete C0000..EFFFF physical snapshot")
    records = []
    for offset in range(0, len(data), 2048):
        if data[offset:offset + 2] != b"\x55\xaa":
            continue
        length = data[offset + 2] * 512
        complete = length > 0 and offset + length <= len(data)
        valid = complete and sum(data[offset:offset + length]) % 256 == 0
        records.append(dict(start=BASE + offset, end=BASE + offset + length,
                            length=length, checksum_valid=valid))
    return records


def page_inventory(data, roms):
    pages = []
    for start in range(BASE, END, 4096):
        overlapping = [r["start"] for r in roms
                       if r["start"] < start + 4096
                       and max(r["end"], r["start"] + 3) > start]
        page = data[start - BASE:start - BASE + 4096]
        pages.append(dict(start=start, rom_headers=overlapping,
                          uniform_byte=page[0] if len(set(page)) == 1 else None,
                          sha256=hashlib.sha256(page).hexdigest(),
                          eligibility="unproven" if not overlapping else "ROM-header overlap"))
    return pages


def rom_rounding_candidates(pages, roms):
    """Header-free slices lost by 16 KiB rounding, not approved UMB pages."""
    return [p["start"] for p in pages if not p["rom_headers"] and any(
        r["start"] < (p["start"] & ~0x3fff) + 0x4000
        and max(r["end"], r["start"] + 3) > (p["start"] & ~0x3fff)
        for r in roms)]


class QMP:
    def __init__(self, connection):
        self.connection = connection
        self.pending = b""
        self.receive()
        self.call("qmp_capabilities")

    def receive(self):
        deadline = time.monotonic() + 15
        while b"\n" not in self.pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.connection], [], [], remaining)[0]:
                raise TimeoutError("QMP response timed out")
            chunk = self.connection.recv(65536)
            if not chunk:
                raise RuntimeError("QMP disconnected")
            self.pending += chunk
        line, self.pending = self.pending.split(b"\n", 1)
        return json.loads(line)

    def call(self, command, arguments=None):
        self.connection.sendall((json.dumps(dict(execute=command, arguments=arguments or {})) + "\n").encode())
        while True:
            response = self.receive()
            if "error" in response:
                raise RuntimeError(response["error"])
            if "return" in response:
                return response["return"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--interface", choices=("ide", "floppy"), default="ide")
    parser.add_argument("--boot-seconds", type=float, default=5)
    args = parser.parse_args()
    if not args.image.is_file() or not 0 < args.boot_seconds <= 30:
        parser.error("an existing image and 0 < boot-seconds <= 30 are required")
    with tempfile.TemporaryDirectory(prefix="uma-topology-") as directory:
        root = Path(directory)
        endpoint, dump = root / "qmp", root / "uma.bin"
        command = ["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
                   "-display", "none", "-monitor", "none", "-serial", "null",
                   "-snapshot", "-no-reboot", "-S", "-boot", "c" if args.interface == "ide" else "a",
                   "-drive", f"if={args.interface},index=0,format=raw,file={str(args.image.resolve()).replace(',', ',,')}",
                   "-qmp", f"unix:{endpoint},server=on,wait=off"]
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 15
            while not endpoint.exists():
                if process.poll() is not None:
                    raise RuntimeError(process.stderr.read().decode())
                if time.monotonic() >= deadline:
                    raise TimeoutError("QMP socket did not appear")
                time.sleep(0.05)
            with socket.socket(socket.AF_UNIX) as connection:
                connection.connect(str(endpoint))
                qmp = QMP(connection)
                qmp.call("cont")
                time.sleep(args.boot_seconds)
                qmp.call("stop")
                topology = qmp.call("human-monitor-command", {"command-line": "info mtree -f"})
                pci = qmp.call("human-monitor-command", {"command-line": "info pci"})
                qmp.call("pmemsave", {"val": BASE, "size": END - BASE, "filename": str(dump)})
                data = dump.read_bytes()
                roms = rom_inventory(data)
                pages = page_inventory(data, roms)
                result = dict(image=str(args.image.resolve()), interface=args.interface,
                              boot_seconds=args.boot_seconds,
                              image_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest(),
                              qemu=subprocess.check_output(["qemu-system-i386", "--version"], text=True).splitlines()[0],
                              command=command, roms=roms, pages=pages,
                              rom_rounding_candidates=rom_rounding_candidates(pages, roms),
                              memory_tree=topology, pci=pci,
                              warning="Timed snapshot, not a boot-success or UMB-safety test. Empty bytes do not establish availability.")
                print(json.dumps(result, indent=2))
                qmp.call("quit")
        finally:
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    main()
