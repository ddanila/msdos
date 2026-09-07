#!/usr/bin/env python3
"""Retire AH=08h operations, check public BDS calls and compare composed memory."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from build_bios_low_image import ROOT, build
from capture_vc_memory_comparison import capture, image_file, parse_capture
from report_dos_bios_residency import parse_map, selected_bios_layout
from test_dos_char_retirement_qemu import install
from test_command_high_resident_qemu import sha
from test_umb_subpage_composition import xms_summary


def run_probe(disk, directory, name, *, reject=False):
    debug = directory / f"{name}.log"
    result = subprocess.run(["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
        "-display", "none", "-monitor", "none", "-serial", "none", "-boot", "c", "-no-reboot",
        "-drive", f"if=ide,format=raw,file={disk}", "-debugcon", f"file:{debug}",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"], capture_output=True, timeout=30)
    (directory / f"{name}-qemu.log").write_bytes(result.stdout + result.stderr)
    trace = debug.read_bytes()
    assert result.returncode == (35 if reject else 33), (name, result.returncode, trace)
    assert trace.endswith(b"F" if reject else b"BIOS_MUX_PASS\r\n"), (name, trace)
    if reject:
        assert b"BIOS_MUX_PASS" not in trace


def probe_image(source, directory, manifest, *, active, retired):
    symbols = manifest["symbols"]
    defines = [f"-DBIOS_ACTIVE={symbols['BIOS_SERVICE_ACTIVE']}", f"-DEXPECT_ACTIVE={int(active)}"]
    if active and retired:
        defines += [f"-DCOLD_START={symbols['BIOS_MUX_BODY']}",
                    f"-DBIOS_END={symbols['BIOS_PERMANENT_END']}",
                    f"-DHIGH_ENTRY={symbols['BIOS_HIGH_MUX_ENTRY']}"]
    probe = directory / "MUX.COM"
    subprocess.run(["nasm", "-f", "bin", *defines, ROOT / "tests/bios_mux_probe.asm", "-o", probe], check=True)
    disk = directory / "probe.img"
    shutil.copyfile(source, disk)
    install(disk, "IO.SYS", (directory / "IO.SYS").read_bytes())
    install(disk, "MUX.COM", probe.read_bytes())
    install(disk, "AUTOEXEC.BAT", b"@ECHO OFF\r\nMUX.COM\r\n")
    return disk


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    args = parser.parse_args()
    assert image_file(args.image, "::MSDOS.SYS") == (ROOT / "src/DOS/MSDOS.SYS").read_bytes()
    work = Path(tempfile.mkdtemp(prefix="bios-mux-retirement-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    provider = work / "EMM386.EXE"
    provider.write_bytes(image_file(args.image, "::DOS/EMM386.EXE"))
    ceiling = work / "CEILING.COM"
    subprocess.run(["nasm", "-f", "bin", ROOT / "tests/memory_ceiling_probe.asm", "-o", ceiling], check=True)
    reports = {}
    for name, retired in (("control", False), ("retired", True)):
        directory = work / name
        manifest = build(directory, early=True, tail_body=True, rebase=True, compact=True,
            high_cds=True, dispatch=True, characters=True, retire_characters=True,
            pack_headers=True, retire_media=True, pack_drive_graph=True, high_stack_pool=True,
            paired_provider=provider, retire_clock=True, retire_mux=retired)
        io = (directory / "IO.SYS").read_bytes()
        if not retired:
            assert io == image_file(args.image, "::IO.SYS"), "control differs from frozen BIOS"
        disk = work / f"input-{name}.img"
        shutil.copyfile(args.image, disk)
        install(disk, "IO.SYS", io)
        for path in ("CONFIG.SYS", "AUTOEXEC.BAT", "MSDOS.SYS", "COMMAND.COM", "DOS/COMMAND.COM",
                     "DOS/HIMEM.SYS", "DOS/EMM386.EXE", "VC/VC.COM"):
            assert image_file(disk, "::" + path) == image_file(args.image, "::" + path), path
        probe = probe_image(disk, directory, manifest, active=True, retired=retired)
        run_probe(probe, directory, "mux")
        if retired:
            high = json.loads((directory / "high/bios-high.json").read_text())
            payload = (directory / "high/bios-high.bin").read_bytes()
            offset = high["exports"]["BIOS_MUX_INSTALL_LINK"]
            assert payload[offset:offset + 3] == b"\x26\x89\x3c"
            assert io.count(payload) == 1
            broken = bytearray(io)
            broken[io.index(payload) + offset + 2] = 4  # AX, not DI, becomes LINK.offset
            negative = directory / "wrong-link.img"
            shutil.copyfile(probe, negative)
            install(negative, "IO.SYS", broken)
            run_probe(negative, directory, "wrong-link", reject=True)
        serial, screen = capture(name, disk, work, ceiling)
        report = parse_capture(serial, screen)
        report["xms"] = xms_summary(serial.read_text(encoding="latin-1"))
        _, symbols = parse_map(directory / "msBIO.map")
        report.update(input_sha256=sha(disk), bios_hma_bytes=manifest["embedded_payload_bytes"],
                      bios_low_bytes=selected_bios_layout(symbols, retired_clock=True)["end"],
                      mux_pass=True, a20_off_pass=retired, wrong_link_rejected=retired)
        reports[name] = report
        (work / "results.json").write_text(json.dumps(reports, indent=2) + "\n")
        print(name, report["largest"], report["upper_free"], flush=True)
    control, retired = reports["control"], reports["retired"]
    gain = retired["largest"] - control["largest"]
    assert gain > 0 and gain == control["bios_low_bytes"] - retired["bios_low_bytes"]
    assert retired["upper_free"] == control["upper_free"]
    assert retired["xms"] == control["xms"]
    fallback = {}
    for mode in ("HIGH", "LOW"):
        directory = work / f"fallback-{mode}"
        manifest = build(directory, early=True, tail_body=True, dispatch=True, characters=True,
            retire_characters=True, pack_headers=True, retire_media=True, pack_drive_graph=True,
            retire_clock=True, retire_mux=True, reservation_limit=0x10)
        disk = probe_image(args.image, directory, manifest, active=False, retired=True)
        himem = subprocess.check_output(["mtype", "-i", str(ROOT / "out/floppy.img"), "::HIMEM.SYS"])
        install(disk, "HIMEM.SYS", himem)
        install(disk, "CONFIG.SYS", f"DEVICE=C:\\HIMEM.SYS /TESTMEM:OFF\r\nDOS={mode}\r\nBUFFERS=15\r\n".encode())
        run_probe(disk, directory, "mux")
        fallback[mode] = dict(image_sha256=sha(disk), active=False, mux_pass=True)
        (work / "fallback.json").write_text(json.dumps(fallback, indent=2) + "\n")


if __name__ == "__main__":
    main()
