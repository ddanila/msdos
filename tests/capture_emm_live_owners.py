#!/usr/bin/env python3
"""Verify our EMM386's live locked-XMS owners against its linked budget.

Uses a disposable floppy copy, freshly installed local managers, and a QEMU
physical-memory snapshot. Never use this map-dependent tool on vendor DOS.
"""
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
from report_emm386_residency import dynamic_table_sizes, parse_map, relocation_budget
from report_himem_residency import parse_symbols

ROOT = Path(__file__).resolve().parents[1]


def startup_config(handle_count=32, mode="RAM"):
    if handle_count not in (32, 48) or mode not in ("RAM", "ON", "OFF", "AUTO"):
        raise ValueError("unsupported live-owner fixture configuration")
    return (f"DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF /NUMHANDLES={handle_count}\r\n"
            f"DEVICE=A:\\EMM386.EXE 1024 {mode} M5\r\n").encode("ascii")


def verify_mode(ram, emm_segment, symbols, mode):
    expected = {"RAM": (True, False), "ON": (True, False),
                "OFF": (False, False), "AUTO": (False, True)}
    if mode not in expected:
        raise ValueError("unsupported mode")
    by_name = {symbol.name: symbol for symbol in symbols}
    flags = {}
    for name in ("Active_Status", "Auto_Mode"):
        symbol = by_name[name]
        flags[name] = ram[(emm_segment + symbol.paragraph) * 16 + symbol.offset]
    if tuple(bool(flags[name]) for name in ("Active_Status", "Auto_Mode")) != expected[mode]:
        raise ValueError(f"initial mode was not retained at capture: {mode}: {flags}")
    return flags


def descriptor(data):
    if len(data) != 8:
        raise ValueError("descriptor must contain eight bytes")
    limit = int.from_bytes(data[:2], "little") | ((data[6] & 15) << 16)
    if data[6] & 0x80:
        limit = (limit << 12) | 4095
    base = int.from_bytes(data[2:5], "little") | (data[7] << 24)
    return dict(base=base, size=limit + 1, access=data[5])


def verify_owners(ram, gdt_base, cr3, emm_segment, xms_segment, segments, symbols, handles,
                  handle_count=32):
    if not (0 < gdt_base < 0xA0000 and 0 < emm_segment < 0xA000
            and 0 < xms_segment < 0xA000 and len(ram) >= 0x100000):
        raise ValueError("invalid low-owner or snapshot bounds")
    by_name = {seg.name: seg for seg in segments}
    syms = {sym.name: sym for sym in symbols}
    budget = relocation_budget(segments, symbols)
    table = (xms_segment << 4) + handles
    allocated = []
    for index in range(handle_count):
        locks, base_kib, size_kib = struct.unpack_from("<BHH", ram, table + index * 5)
        if base_kib:
            allocated.append(dict(handle=index + 1, base=0x100000 + base_kib * 1024,
                                  size=size_kib * 1024, locks=locks))
    if len(allocated) != 1 or allocated[0]["locks"] != 1:
        raise ValueError("fixed fixture requires exactly one once-locked XMS allocation")
    block = allocated[0]
    total = syms["_total_pages"]
    total_pages = struct.unpack_from("<H", ram,
        (emm_segment + total.paragraph) * 16 + total.offset)[0]
    tail = block["base"] + total_pages * 16384
    end = block["base"] + block["size"]
    if end - tail != budget["reserved"] or end > len(ram):
        raise ValueError("live XMS tail disagrees with MEMREQ reservation")
    desc = {name: descriptor(ram[gdt_base + selector:gdt_base + selector + 8])
            for name, selector in (("idt", 0x10), ("tss", 0x20),
                                   ("code", 0x38), ("data", 0x40), ("stack", 0x48))}
    if any(not row["access"] & 0x80 for row in desc.values()):
        raise ValueError("an owner descriptor is not present")
    page_base = (tail + 4096) & ~4095
    code_base = (tail + budget["page_request"] + 3) & ~3
    if cr3 != page_base or desc["code"]["base"] != code_base:
        raise ValueError("live paging/code bases disagree with allocation order")
    for name, segment in (("idt", "IDT"), ("tss", "TSS")):
        area = syms["Page_Area"]
        original_page = ((emm_segment + area.paragraph) * 16 + area.offset + 4095) & ~4095
        expected = page_base + (emm_segment + by_name[segment].paragraph) * 16 - original_page
        if desc[name]["base"] != expected:
            raise ValueError(f"live {name} base disagrees with relocated page image")
        if desc[name]["size"] != by_name[segment].size or expected + desc[name]["size"] > code_base:
            raise ValueError(f"live {name} extent escapes its allocation")
    expected_data = (emm_segment + by_name["_DATA"].paragraph) * 16
    if desc["data"]["base"] != expected_data or desc["stack"]["base"] >= 0xA0000:
        raise ValueError("data/transition stack no longer match the retained-low design")
    def low_word(name):
        symbol = syms[name]
        return struct.unpack_from("<H", ram,
            (emm_segment + symbol.paragraph) * 16 + symbol.offset)[0]
    data_start = expected_data + low_word("_save_map")
    data_end = expected_data + low_word("_emm_brk")
    if not expected_data <= data_start < data_end <= desc["stack"]["base"]:
        raise ValueError("dynamic table object is not wholly below the low stack")
    counts = {}
    for key, name in (("handles", "_handle_table_size"), ("alternate_registers", "_altreg_count"),
                      ("physical_pages", "_physical_page_count"),
                      ("page_assignments", "_physical_page_exception_count"),
                      ("dma_pages", "DMA_PAGE_COUNT")):
        symbol = syms[name]
        counts[key] = ram[(emm_segment + symbol.paragraph) * 16 + symbol.offset]
    counts["ems_pages"] = total_pages
    if sum(size for size, _ in dynamic_table_sizes(**counts)) != data_end - data_start:
        raise ValueError("live counts do not account for the complete table extent")
    return dict(xms=block, ems_pool_bytes=total_pages * 16384, relocation_start=tail,
                relocation_end=end, cr3=cr3, descriptors=desc, budget=budget,
                low_tables=dict(start=data_start, end=data_end, size=data_end-data_start),
                table_to_stack_gap=desc["stack"]["base"] - data_end,
                table_counts=counts,
                unused_start=tail + budget["page_request"] + budget["text_request"],
                unused_end=end)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="our repaired DOS floppy image")
    parser.add_argument("--himem-handles", type=int, choices=(32, 48), default=32,
                        help="shift the manager load address without changing its EMS capacities")
    parser.add_argument("--mode", choices=("RAM", "ON", "OFF", "AUTO"), default="RAM",
                        help="isolate initial-mode effects on table and stack placement")
    args = parser.parse_args()
    subprocess.run(["make", "memm", "test-himem-residency"], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL)
    work = Path(tempfile.mkdtemp(prefix="emm-live-owners-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    image = work / "boot.img"
    shutil.copyfile(args.image, image)
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    def install(source, target, data=None):
        subprocess.run(["mcopy", "-o", "-i", str(image), str(source), "::" + target],
                       input=data, env=env, check=True)
    probe = work / "OWNERS.COM"
    subprocess.run(["nasm", "-f", "bin", ROOT / "tests/emm386_live_owner_probe.asm",
                    "-o", probe], check=True)
    emm = ROOT / "src/MEMM/MEMM/EMM386.EXE"
    himem = ROOT / "out/himem-residency.sys"
    install(emm, "EMM386.EXE")
    install(himem, "HIMEM.SYS")
    install(probe, "OWNERS.COM")
    config = startup_config(args.himem_handles, args.mode)
    install("-", "CONFIG.SYS", config)
    install("-", "AUTOEXEC.BAT", b"@ECHO OFF\r\nCTTY AUX\r\nOWNERS.COM\r\n")
    qmp_path = work / "qmp"
    serial = work / "serial.log"
    command = ["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
               "-display", "none", "-monitor", "none", "-boot", "a", "-no-reboot",
               "-qmp", f"unix:{qmp_path},server=on,wait=off", "-serial", f"file:{serial}",
               "-drive", f"if=floppy,format=raw,file={image},cache=writethrough"]
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            trace = serial.read_text(errors="replace") if serial.exists() else ""
            if "EMM_LIVE_OWNER_READY" in trace:
                break
            if process.poll() is not None:
                raise RuntimeError("guest exited before owner capture")
            time.sleep(0.1)
        else:
            raise TimeoutError("guest did not reach owner checkpoint")
        with socket.socket(socket.AF_UNIX) as connection:
            connection.connect(str(qmp_path))
            qmp = QMP(connection)
            qmp.call("stop")
            registers = qmp.call("human-monitor-command", {"command-line": "info registers"})
            qmp.call("human-monitor-command", {"command-line": f'pmemsave 0 8388608 "{work / "ram.bin"}"'})
        (work / "registers.txt").write_text(registers)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    segments, symbols = parse_map(ROOT / "src/MEMM/MEMM/EMM386.MAP")
    himem_symbols, himem_numbers = parse_symbols(ROOT / "out/himem-residency.lst")
    if [himem_numbers[name] for name in ("HANDLE_LOCK", "HANDLE_BASE", "HANDLE_LENGTH", "HANDLE_SIZE")] != [0, 1, 3, 5]:
        raise ValueError("HIMEM handle record layout changed")
    ram = (work / "ram.bin").read_bytes()
    emm_segment = int(re.search(r"EMM_SEG=([0-9A-F]{4})", trace)[1], 16)
    result = verify_owners(ram,
        int(re.search(r"GDT=\s*([0-9a-fA-F]+)", registers)[1], 16),
        int(re.search(r"CR3=([0-9a-fA-F]+)", registers)[1], 16),
        emm_segment,
        int(re.search(r"XMS_SEG=([0-9A-F]{4})", trace)[1], 16),
        segments, symbols, himem_symbols["handles"][0], args.himem_handles)
    result["mode_flags"] = verify_mode(ram, emm_segment, symbols, args.mode)
    if result["ems_pool_bytes"] != 1048576:
        raise ValueError(f"fixed profile was not installed: {result}")
    result["inputs"] = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in (args.image, emm, himem, ROOT / "src/MEMM/MEMM/EMM386.MAP")}
    result["config"] = config.decode("ascii")
    result["emulator"] = subprocess.check_output(["qemu-system-i386", "--version"], text=True).splitlines()[0]
    (work / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
