#!/usr/bin/env python3
"""Read the initialized BIOS BDS / DOS DPB graph from a frozen composed image.

This is an ownership census, not a relocation test or a memory-saving result.
QEMU uses disposable drive snapshots; the supplied image is never modified.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

from capture_vc_memory_comparison import image_file
from report_dos_bios_residency import parse_map
from screen_expect import QMPConnection

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("bios", type=Path, help="matching isolated BIOS build directory")
    parser.add_argument("dos_map", type=Path, help="map with matching MSDOS.SYS alongside")
    parser.add_argument("--two-disks", action="store_true")
    args = parser.parse_args()
    assert image_file(args.image, "::IO.SYS") == (args.bios / "IO.SYS").read_bytes()
    assert image_file(args.image, "::MSDOS.SYS") == args.dos_map.with_suffix(".SYS").read_bytes()
    _, bios = parse_map(args.bios / "msBIO.map")
    _, dos = parse_map(args.dos_map)
    bios = {key.upper(): value for key, value in bios.items()}
    work = Path(tempfile.mkdtemp(prefix="bios-descriptors-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    socket = work / "qmp"
    command = ["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
               "-display", "none", "-monitor", "none", "-serial", "none",
               "-qmp", f"unix:{socket},server=on,wait=off", "-no-reboot", "-boot", "c"]
    for index in range(2 if args.two_disks else 1):
        command += ["-drive", f"if=ide,index={index},format=raw,file={args.image.resolve()},snapshot=on"]
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        subprocess.run([sys.executable, ROOT / "tests/screen_expect.py", socket,
                        work / "screen.log", "1Help", "hmp:stop"], check=True, timeout=90)
        qmp = QMPConnection(str(socket))
        try:
            answer = qmp.human_cmd(f'pmemsave 0 1048576 "{work / "memory.bin"}"')
            assert not answer.strip(), answer
        finally:
            qmp.close()
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    memory = (work / "memory.bin").read_bytes()
    assert len(memory) == 1048576

    def word(address):
        return struct.unpack_from("<H", memory, address)[0]

    def pointer(address):
        offset, segment = struct.unpack_from("<HH", memory, address)
        return segment, offset

    def walk(root, size, link, drive):
        result, seen = [], set()
        segment, offset = root
        while offset != 0xffff:
            address = 16 * segment + offset
            assert address not in seen and len(result) < 26
            # pmemsave reads physical RAM, not EMM386's translated UMB view.
            # This census deliberately accepts only the present low graph.
            assert 0 < address and address + size <= 0xa0000
            seen.add(address)
            result.append(dict(segment=segment, offset=offset, bytes=size,
                               drive=memory[address + drive],
                               raw=memory[address:address + size].hex()))
            segment, offset = pointer(address + link)
        return result

    low_dos = word(0x700 + bios["BIOS_REBASED_TO"])
    assert 0x70 < low_dos < 0xa000, low_dos
    # MSBDS.INC: BDS_TYPE is 100 bytes; LINK=0, DRIVELET=5.
    # DPB.INC: DPBSIZ=33, DPB_NEXT_DPB=25, DPB_DRIVE=0.
    bds = walk(pointer(0x700 + bios["START_BDS"]), 100, 0, 5)
    dpbs = walk(pointer(16 * low_dos + dos["DPBHEAD"]), 33, 25, 0)
    count = memory[0x700 + bios["DRVMAX"]]
    assert len(bds) == len(dpbs) == count
    assert [row["drive"] for row in bds] == list(range(count))
    assert [row["drive"] for row in dpbs] == list(range(count))
    assert count == (4 if args.two_disks else 3), count
    record = dict(image_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest(),
                  two_disks=args.two_disks, bios_low_segment=0x70, dos_low_segment=low_dos,
                  bds=bds, dpbs=dpbs, live_bds_bytes=100 * count,
                  live_bios_overflow_dpb_bytes=max(0, count - 2) * 33,
                  warning="Read-only census; no source allocation was released.")
    (work / "graph.json").write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps(record, indent=2), flush=True)


if __name__ == "__main__":
    main()
