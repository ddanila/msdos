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
    parser.add_argument("--mode", choices=("ON", "OFF", "AUTO"), default="ON")
    parser.add_argument("--leave-active", action="store_true",
                        help="negative control: fail to restore OFF/idle AUTO")
    parser.add_argument("--fail-after-map", action="store_true")
    parser.add_argument("--mapped", action="store_true", help="exercise all mapped endpoint combinations")
    parser.add_argument("--bypass-mapping", action="store_true",
                        help="negative control: misclassify the mapped source as physical")
    parser.add_argument("--bad-data", action="store_true",
                        help="negative control: corrupt one returned byte; the run must fail")
    parser.add_argument("--deny-later-page", action="store_true",
                        help="deny the mapped source's second page; require zero writes")
    parser.add_argument("--bypass-preflight", action="store_true",
                        help="negative control with --deny-later-page: allow partial writes")
    parser.add_argument("--deny-destination", action="store_true",
                        help="with --deny-later-page, reject the destination instead")
    parser.add_argument("--alias-overlap", action="store_true",
                        help="require rejection without writes for overlapping EMS aliases")
    parser.add_argument("--alias-mode", choices=("overlap", "reverse", "identity", "disjoint"),
                        default="overlap", help="variant of --alias-overlap")
    parser.add_argument("--bypass-aliases", action="store_true",
                        help="negative control: omit whole-range alias checking")
    args = parser.parse_args()
    if args.mode != "ON" and args.mapped:
        parser.error("EMS-mapped tests require ON; inactive modes test physical service entry")
    if args.leave_active and args.mode == "ON":
        parser.error("--leave-active requires OFF or AUTO")
    if args.fail_after_map and args.bad_data:
        parser.error("the data control requires a completed copy")
    if args.fail_after_map and args.mapped or args.bypass_mapping and not args.mapped:
        parser.error("mapped tests require successful copying; bypass requires --mapped")
    if args.deny_later_page and (not args.mapped or args.bypass_mapping or args.bad_data):
        parser.error("page rejection requires --mapped without data/mapping corruption")
    if args.bypass_preflight and not args.deny_later_page:
        parser.error("--bypass-preflight requires --deny-later-page")
    if args.deny_destination and not args.deny_later_page:
        parser.error("--deny-destination requires --deny-later-page")
    if args.alias_overlap and (not args.mapped or args.deny_later_page or args.bypass_mapping or args.bad_data):
        parser.error("alias overlap requires --mapped without other fault controls")
    if (args.alias_mode != "overlap" or args.bypass_aliases) and not args.alias_overlap:
        parser.error("alias mode/bypass requires --alias-overlap")
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
    if args.leave_active:
        flags += " -DEMM_XMS_COPY_LEAVE_ACTIVE"
    if args.deny_later_page:
        flags += " -DEMM_XMS_COPY_DENY_ALIGNED_PAGE"
    if args.bypass_preflight:
        flags += " -DEMM_XMS_COPY_SKIP_PREFLIGHT -DEMM_XMS_COPY_SKIP_ALIASES"
    if args.bypass_aliases:
        flags += " -DEMM_XMS_COPY_SKIP_ALIASES"
    if args.deny_destination:
        flags += " -DEMM_XMS_COPY_DENY_DESTINATION"
    with (work / "build.log").open("w") as log:
        subprocess.run([str(ROOT / "bin/jwasm-masm"), flags,
                        f"MOVEB.ASM,{work / 'MEMM/MOVEB.OBJ'};"],
                       cwd=ROOT / "src/MEMM/MEMM", check=True, stdout=log, stderr=subprocess.STDOUT)
        subprocess.run([str(ROOT / "bin/jwasm-masm"), flags + " -DRRTRAP_LOW_ONLY",
                        f"RRTRAP.ASM,{work / 'MEMM/RRTRAP.OBJ'};"],
                       cwd=ROOT / "src/MEMM/MEMM", check=True, stdout=log, stderr=subprocess.STDOUT)
        subprocess.run([str(ROOT / "bin/wlink"), "/NOI /PACKDATA:1 @EMM386.LNK"],
                       cwd=work / "MEMM", check=True, stdout=log, stderr=subprocess.STDOUT)
    candidate = work / "MEMM/EMM386.EXE"
    _, symbols = parse_map(work / "MEMM/EMM386.MAP")
    symbols = {symbol.name: symbol for symbol in symbols}
    code_size = symbols["XmsCopyPhysicalEnd"].offset - symbols["XmsCopyPhysical"].offset
    client_size = symbols["XmsCopyClientEnd"].offset - symbols["XmsCopyClient"].offset
    inactive_size = symbols["XmsI15InactiveEnd"].offset - symbols["XmsI15InactiveStart"].offset
    return_size = symbols["FarXmsReturnRealEnd"].offset - symbols["FarXmsReturnReal"].offset
    probe = work / "probe.com"
    subprocess.run(["nasm", "-f", "bin", *(["-DEXPECT_MAP_FAILURE"] if args.fail_after_map else []),
                    f"-DEXPECT_MODE={dict(ON=0, OFF=1, AUTO=3)[args.mode]}",
                    *(["-DWRONG_DATA"] if args.bad_data else []),
                    *(["-DMAPPED_ENDPOINT"] if args.mapped else []),
                    *(["-DBYPASS_MAPPING"] if args.bypass_mapping else []),
                    *(["-DEXPECT_PAGE_FAILURE"] if args.deny_later_page else []),
                    *(["-DEXPECT_DEST_PAGE_FAILURE"] if args.deny_destination else []),
                    *(["-DALIAS_OVERLAP"] if args.alias_overlap else []),
                    *([f"-DALIAS_{args.alias_mode.upper()}"]
                      if args.alias_overlap and args.alias_mode != "overlap" else []),
                    *(["-DALIAS_SUCCESS"] if args.alias_mode in ("identity", "disjoint") else []),
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
    install("-", "CONFIG.SYS", ("DEVICE=HIMEM.SYS /TESTMEM:OFF\r\n"
                               f"DEVICE=EMM386.EXE 1024 {args.mode} M5\r\n").encode("ascii"))
    install("-", "AUTOEXEC.BAT", b"@ECHO OFF\r\nPROBE.COM\r\n")
    # The private build uses the production NoBugMode selector layout.
    selectors = (ROOT / "src/MEMM/MEMM/VDMSEL.INC").read_text()
    assert re.search(r"RCODEA_GSEL\s+equ\s+058h", selectors)
    assert re.search(r"MBSRC_GSEL\s+equ\s+RCODEA_GSEL\+18h", selectors)
    assert re.search(r"MBTAR_GSEL\s+equ\s+RCODEA_GSEL\+20h", selectors)
    endpoint, debug = work / "qmp", work / "debug.bin"
    report = dict(passed=False, mode=args.mode, fail_after_map=args.fail_after_map, core_bytes=code_size,
                  leave_active=args.leave_active, inactive_entry_bytes=inactive_size,
                  real_return_adapter_bytes=return_size,
                  client_bytes=client_size, mapped=args.mapped, bypass_mapping=args.bypass_mapping,
                  deny_later_page=args.deny_later_page, bypass_preflight=args.bypass_preflight,
                  deny_destination=args.deny_destination,
                  alias_overlap=args.alias_overlap,
                  alias_mode=args.alias_mode, bypass_aliases=args.bypass_aliases,
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
                cr0 = int(re.search(r"CR0=([0-9a-fA-F]+)", regs)[1], 16)
                if bool(cr0 & 1) != (args.mode == "ON"):
                    raise ValueError(f"copy failed to retain requested {args.mode} execution mode")
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
                        matches.append((base, struct.unpack_from("<H", ram, offset + 12)[0], offset))
                    offset += 1
                if len(matches) != 1:
                    raise ValueError(f"expected one live high-allocation witness: {matches}")
                base, frame, witness_offset = matches[0]
                ranges = [ram[base+start:base+start+8192] for start in (4093, 16391)]
                expected_data = bytes((n & 255) ^ (n >> 8) ^ 0x5a for n in range(8192))
                expected_ranges = [expected_data, expected_data]
                if args.mapped and not (args.deny_later_page or args.alias_overlap):
                    expected_ranges[0] = bytes(value ^ 255 for value in expected_data)
                if (args.deny_later_page or args.alias_overlap) and phase in ("N", "B"):
                    before = next(row for row in report["checkpoints"] if row["phase"] == "M")
                    if [hashlib.sha256(data).hexdigest() for data in ranges] != before["range_hashes"]:
                        raise ValueError("later-page rejection wrote earlier destination bytes")
                if phase in ("N", "B") and not args.fail_after_map and ranges != expected_ranges:
                    raise ValueError("actual high physical RAM does not contain both copied ranges")
                hashes = [hashlib.sha256(data).hexdigest() for data in ranges]
                cr3 = int(re.search(r"CR3=([0-9a-fA-F]+)", regs)[1], 16)
                gdt = int(re.search(r"GDT=\s*([0-9a-fA-F]+)", regs)[1], 16)
                if gdt >= 0xA0000:
                    raise ValueError("expected the installed low GDT")
                windows = copy_window_candidates(ram, cr3)
                client_frames = []
                client_hashes = []
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
                        client_hashes.append(hashlib.sha256(ram[(pte & ~4095):(pte & ~4095)+4096]).hexdigest())
                    if client_frames == list(range(frame << 4, (frame << 4) + 32768, 4096)):
                        raise ValueError("the witness did not actually remap its endpoints")
                    if phase == "N" and client_frames != report["checkpoints"][-1]["client_frames"]:
                        raise ValueError("copying changed the application's EMS mappings")
                    if args.alias_overlap and client_frames[:4] != client_frames[4:]:
                        raise ValueError("overlap witness lacks identical EMS physical backing")
                    if args.alias_overlap and phase == "N":
                        src_offset = 7 if args.alias_mode == "reverse" else 4093
                        dst_offset = 4093 if args.alias_mode in ("reverse", "identity") else 7
                        length = 64 if args.alias_mode == "disjoint" else 8192
                        report["alias_overlap_observation"] = dict(
                            carry=bool(struct.unpack_from("<H", ram, witness_offset + 16)[0] & 1),
                            error=ram[witness_offset + 18],
                            source_linear=(frame << 4) + src_offset,
                            destination_linear=(frame << 4) + 0x4000 + dst_offset,
                            length=length,
                            physical_pages=client_frames,
                            changed_window_pages=[index for index, (before, after) in enumerate(
                                zip(report["checkpoints"][-1]["client_hashes"], client_hashes))
                                if before != after])
                        if args.alias_mode == "disjoint":
                            before_ram = (work / "M-ram.bin").read_bytes()
                            expected_ram = bytearray(before_ram)
                            for byte in range(length):
                                source = src_offset + byte
                                dest = dst_offset + byte
                                expected_ram[client_frames[dest // 4096] + dest % 4096] = before_ram[
                                    client_frames[source // 4096] + source % 4096]
                            if any(ram[page:page+4096] != expected_ram[page:page+4096]
                                   for page in client_frames):
                                raise ValueError("disjoint same-page alias copy changed unexpected bytes")
                    if (args.alias_overlap and phase == "N"
                            and args.alias_mode != "disjoint"
                            and client_hashes != report["checkpoints"][-1]["client_hashes"]):
                        raise ValueError("overlapping EMS aliases modified backing before rejection")
                    if (args.deny_later_page and phase == "N"
                            and client_hashes != report["checkpoints"][-1]["client_hashes"]):
                        raise ValueError("later-page rejection wrote mapped destination bytes")
                row = dict(phase=phase, cr0=cr0, windows=windows, descriptors=ram[gdt+0x70:gdt+0x80].hex(),
                           physical_block_base=base, range_hashes=hashes, client_frames=client_frames,
                           client_hashes=client_hashes)
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
