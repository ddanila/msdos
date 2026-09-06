#!/usr/bin/env python3
"""Test development physical copy windows; no public XMS dispatch is replaced."""
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

from capture_emm_live_owners import copy_window_candidates
from capture_uma_topology import QMP
from report_emm386_residency import parse_map

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, default=ROOT / "out/floppy.img")
    parser.add_argument("--fail-after-map", action="store_true")
    parser.add_argument("--mapped", action="store_true", help="exercise all mapped endpoint combinations")
    parser.add_argument("--bypass-mapping", action="store_true",
                        help="negative control: misclassify the mapped source as physical")
    parser.add_argument("--bad-data", action="store_true",
                        help="negative control: corrupt one returned byte; the run must fail")
    args = parser.parse_args()
    if args.fail_after_map and args.bad_data:
        parser.error("the data control requires a completed copy")
    if args.fail_after_map and args.mapped or args.bypass_mapping and not args.mapped:
        parser.error("mapped tests require successful copying; bypass requires --mapped")
    subprocess.run(["make", "memm"], cwd=ROOT, check=True)
    normal = ROOT / "src/MEMM/MEMM/EMM386.EXE"
    normal_hash = hashlib.sha256(normal.read_bytes()).hexdigest()
    work = Path(tempfile.mkdtemp(prefix="xms-copy-windows-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    for name in ("MEMM", "EMM"):
        (work / name).mkdir()
        for path in (ROOT / "src/MEMM" / name).iterdir():
            if path.suffix.upper() in (".OBJ", ".LIB", ".LNK"):
                shutil.copyfile(path, work / name / path.name)
    flags = "-Mx -t -DI386 -DNoBugMode -DNOHIMEM -I. -I..\\EMM -DEMM_XMS_COPY_TEST"
    if args.fail_after_map:
        flags += " -DEMM_XMS_COPY_FAIL_AFTER_MAP"
    with (work / "build.log").open("w") as log:
        subprocess.run([str(ROOT / "bin/jwasm-masm"), flags,
                        f"MOVEB.ASM,{work / 'MEMM/MOVEB.OBJ'};"],
                       cwd=ROOT / "src/MEMM/MEMM", check=True, stdout=log, stderr=subprocess.STDOUT)
        subprocess.run([str(ROOT / "bin/wlink"), "/NOI /PACKDATA:1 @EMM386.LNK"],
                       cwd=work / "MEMM", check=True, stdout=log, stderr=subprocess.STDOUT)
    candidate = work / "MEMM/EMM386.EXE"
    _, symbols = parse_map(work / "MEMM/EMM386.MAP")
    symbols = {symbol.name: symbol for symbol in symbols}
    code_size = symbols["XmsCopyPhysicalEnd"].offset - symbols["XmsCopyPhysical"].offset
    client_size = symbols["XmsCopyClientEnd"].offset - symbols["XmsCopyClient"].offset
    probe = work / "probe.com"
    subprocess.run(["nasm", "-f", "bin", *(["-DEXPECT_MAP_FAILURE"] if args.fail_after_map else []),
                    *(["-DWRONG_DATA"] if args.bad_data else []),
                    *(["-DMAPPED_ENDPOINT"] if args.mapped else []),
                    *(["-DBYPASS_MAPPING"] if args.bypass_mapping else []),
                    str(ROOT / "tests/xms_copy_windows_probe.asm"), "-o", str(probe)], check=True)
    image = work / "boot.img"
    shutil.copyfile(args.image, image)
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    def install(source, target, data=None):
        subprocess.run(["mcopy", "-o", "-i", str(image), str(source), "::" + target],
                       input=data, env=env, check=True)
    install(candidate, "EMM386.EXE")
    install(ROOT / "src/DEV/HIMEM/HIMEM.SYS", "HIMEM.SYS")
    install(probe, "PROBE.COM")
    install("-", "CONFIG.SYS", b"DEVICE=HIMEM.SYS /TESTMEM:OFF\r\nDEVICE=EMM386.EXE 1024 ON M5\r\n")
    install("-", "AUTOEXEC.BAT", b"@ECHO OFF\r\nPROBE.COM\r\n")
    # The private build uses the production NoBugMode selector layout.
    selectors = (ROOT / "src/MEMM/MEMM/VDMSEL.INC").read_text()
    assert re.search(r"RCODEA_GSEL\s+equ\s+058h", selectors)
    assert re.search(r"MBSRC_GSEL\s+equ\s+RCODEA_GSEL\+18h", selectors)
    assert re.search(r"MBTAR_GSEL\s+equ\s+RCODEA_GSEL\+20h", selectors)
    endpoint, debug = work / "qmp", work / "debug.bin"
    report = dict(passed=False, fail_after_map=args.fail_after_map, core_bytes=code_size,
                  client_bytes=client_size, mapped=args.mapped, bypass_mapping=args.bypass_mapping,
                  normal_sha256=normal_hash, candidate_sha256=hashlib.sha256(candidate.read_bytes()).hexdigest(),
                  probe_sha256=hashlib.sha256(probe.read_bytes()).hexdigest(), bad_data=args.bad_data,
                  image_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest(),
                  himem_sha256=hashlib.sha256((ROOT / "src/DEV/HIMEM/HIMEM.SYS").read_bytes()).hexdigest(),
                  emulator=subprocess.check_output(["qemu-system-i386", "--version"], text=True).splitlines()[0],
                  ram_mib=32, checkpoints=[])
    process = subprocess.Popen([
        "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "32",
        "-display", "none", "-monitor", "none", "-serial", "none",
        "-drive", f"if=floppy,format=raw,file={image}", "-boot", "a", "-no-reboot",
        "-qmp", f"unix:{endpoint},server=on,wait=off", "-debugcon", f"file:{debug}",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
    ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 30
        while not endpoint.exists():
            if process.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("QMP startup failed")
            time.sleep(.05)
        with socket.socket(socket.AF_UNIX) as connection:
            connection.connect(str(endpoint))
            qmp = QMP(connection)
            for expected in ((b"A", b"AM", b"AMN", b"AMNB") if args.mapped else (b"A", b"AB")):
                deadline = time.monotonic() + 30
                while True:
                    trace = debug.read_bytes() if debug.exists() else b""
                    if trace == expected:
                        break
                    if not expected.startswith(trace) or process.poll() is not None:
                        raise ValueError(f"copy guest failed: {trace!r}")
                    if time.monotonic() > deadline:
                        raise TimeoutError(f"copy checkpoint missing: {trace!r}")
                    time.sleep(.05)
                phase = chr(expected[-1])
                qmp.call("stop")
                regs = qmp.call("human-monitor-command", {"command-line": "info registers"})
                (work / f"{phase}-registers.txt").write_text(regs)
                dump = work / f"{phase}-ram.bin"
                qmp.call("human-monitor-command", {"command-line": f'pmemsave 0 33554432 "{dump}"'})
                ram = dump.read_bytes()
                # Independently check physical RAM: a round trip alone could
                # pass if both directions truncated the same high address.
                matches = []
                offset = 0
                while True:
                    offset = ram.find(b"XWPROBE!", offset)
                    if offset < 0:
                        break
                    base = struct.unpack_from("<I", ram, offset + 8)[0]
                    if 0x1000000 <= base <= len(ram) - 32768:
                        matches.append((base, struct.unpack_from("<H", ram, offset + 12)[0]))
                    offset += 1
                if len(matches) != 1:
                    raise ValueError(f"expected one live high-allocation witness: {matches}")
                base, frame = matches[0]
                ranges = [ram[base+start:base+start+8192] for start in (4093, 16391)]
                expected_data = bytes((n & 255) ^ (n >> 8) ^ 0x5a for n in range(8192))
                expected_ranges = [expected_data, expected_data]
                if args.mapped:
                    expected_ranges[0] = bytes(value ^ 255 for value in expected_data)
                if phase in ("N", "B") and not args.fail_after_map and ranges != expected_ranges:
                    raise ValueError("actual high physical RAM does not contain both copied ranges")
                hashes = [hashlib.sha256(data).hexdigest() for data in ranges]
                cr3 = int(re.search(r"CR3=([0-9a-fA-F]+)", regs)[1], 16)
                gdt = int(re.search(r"GDT=\s*([0-9a-fA-F]+)", regs)[1], 16)
                if gdt >= 0xA0000:
                    raise ValueError("expected the installed low GDT")
                windows = copy_window_candidates(ram, cr3)
                client_frames = []
                if phase in ("M", "N"):
                    if not 0x4000 <= frame <= 0xe800:
                        raise ValueError("invalid EMS frame witness")
                    pde = struct.unpack_from("<I", ram, cr3 & ~4095)[0]
                    if pde & 7 != 7:
                        raise ValueError("client page directory is not present/user/writable")
                    for page in range(frame >> 8, (frame >> 8) + 8):
                        pte = struct.unpack_from("<I", ram, (pde & ~4095) + page * 4)[0]
                        if pte & 7 != 7:
                            raise ValueError("mapped EMS endpoint is not present/user/writable")
                        client_frames.append(pte & ~4095)
                    if client_frames == list(range(frame << 4, (frame << 4) + 32768, 4096)):
                        raise ValueError("the witness did not actually remap its endpoints")
                    if phase == "N" and client_frames != report["checkpoints"][-1]["client_frames"]:
                        raise ValueError("copying changed the application's EMS mappings")
                row = dict(phase=phase, windows=windows, descriptors=ram[gdt+0x70:gdt+0x80].hex(),
                           physical_block_base=base, range_hashes=hashes, client_frames=client_frames)
                report["checkpoints"].append(row)
                if row["descriptors"] != report["checkpoints"][0]["descriptors"]:
                    raise ValueError("copy descriptors were not restored")
                first = report["checkpoints"][0]
                if base != first["physical_block_base"] or (args.fail_after_map and hashes != first["range_hashes"]):
                    raise ValueError("allocation identity changed or failed mapping wrote data")
                qmp.call("cont")
                qmp.call("send-key", {"keys": [{"type": "qcode", "data": "spc"}], "hold-time": 1})
            if process.wait(timeout=10) != 33:
                raise ValueError("copy guest did not release its XMS owners and finish")
        assert hashlib.sha256(normal.read_bytes()).hexdigest() == normal_hash
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
    print(f"PASS: copy windows restored; physical core {code_size}, typed-address layer {client_size} bytes")


if __name__ == "__main__":
    main()
