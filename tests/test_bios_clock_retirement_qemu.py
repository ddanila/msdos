#!/usr/bin/env python3
"""Retire the complete low clock conversion owner and measure a frozen profile."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from build_bios_low_image import ROOT, build
from capture_vc_memory_comparison import capture, image_file, parse_capture
from test_dos_char_retirement_qemu import install
from test_command_high_resident_qemu import sha
from test_umb_subpage_composition import xms_summary
from report_dos_bios_residency import parse_map, selected_bios_layout


def run_clock(image, directory, name="clock", reject=False):
    debug = directory / f"{name}-debug.log"
    result = subprocess.run(["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
        "-display", "none", "-monitor", "none", "-serial", "none", "-boot", "c", "-no-reboot",
        "-drive", f"if=ide,format=raw,file={image}", "-debugcon", f"file:{debug}",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"], capture_output=True, timeout=30)
    (directory / f"{name}-qemu.log").write_bytes(result.stdout+result.stderr)
    trace = debug.read_bytes()
    if reject:
        assert result.returncode == 35 and trace.endswith(b"F"), name
        assert b"BIOS_CLOCK_CONVERSION_PASS" not in trace
    else:
        assert result.returncode == 33 and trace.endswith(b"BIOS_CLOCK_CONVERSION_PASS\r\n"), name


def clock_probe(directory, manifest, active, retired):
    symbols = manifest["symbols"]
    defines = [f"-DBIOS_ACTIVE={symbols['BIOS_SERVICE_ACTIVE']}", f"-DEXPECT_ACTIVE={int(active)}"]
    if active and retired:
        defines += [f"-DLEGACY_BCD={symbols['BINTOBCD']}", f"-DLEGACY_DAY={symbols['DAYCNTTODAY']}"]
    probe = directory / "CLOCK.COM"
    subprocess.run(["nasm", "-f", "bin", *defines,
                    ROOT / "tests/bios_clock_conversion.asm", "-o", probe], check=True)
    return probe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    args = parser.parse_args()
    assert image_file(args.image, "::MSDOS.SYS") == (ROOT / "src/DOS/MSDOS.SYS").read_bytes()
    work = Path(tempfile.mkdtemp(prefix="bios-clock-retirement-", dir=ROOT / "out"))
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
            paired_provider=provider, retire_clock=retired)
        io = (directory / "IO.SYS").read_bytes()
        clock = clock_probe(directory, manifest, True, retired)
        if not retired:
            assert io == image_file(args.image, "::IO.SYS"), "control differs from frozen BIOS"
        disk = work / f"input-{name}.img"
        shutil.copyfile(args.image, disk)
        install(disk, "IO.SYS", io)
        for path in ("CONFIG.SYS", "AUTOEXEC.BAT", "MSDOS.SYS", "COMMAND.COM", "DOS/COMMAND.COM",
                     "DOS/HIMEM.SYS", "DOS/EMM386.EXE", "VC/VC.COM"):
            assert image_file(disk, "::"+path) == image_file(args.image, "::"+path), path
        probe_disk = directory / "clock.img"
        shutil.copyfile(disk, probe_disk)
        install(probe_disk, "CLOCK.COM", clock.read_bytes())
        install(probe_disk, "AUTOEXEC.BAT", b"@ECHO OFF\r\nCLOCK.COM\r\n")
        run_clock(probe_disk, directory)
        if retired:
            payload = (directory / "high/bios-high.bin").read_bytes()
            assert io.count(payload) == 1
            # Change only the high BCD conversion's radix, not its cold copy.
            opcode = b"\xd4\x0a\xd5\x10\xc3"
            assert payload.count(opcode) == 1
            broken = bytearray(io)
            broken[io.index(payload)+payload.index(opcode)+3] = 10
            negative = directory / "wrong-radix.img"
            shutil.copyfile(probe_disk, negative)
            install(negative, "IO.SYS", broken)
            run_clock(negative, directory, "wrong-radix", reject=True)
        serial, screen = capture(name, disk, work, ceiling)
        report = parse_capture(serial, screen)
        report["xms"] = xms_summary(serial.read_text(encoding="latin-1"))
        report["input_sha256"] = sha(disk)
        report["bios_hma_bytes"] = manifest["embedded_payload_bytes"]
        _, linked_symbols = parse_map(directory / "msBIO.map")
        report["bios_low_bytes"] = selected_bios_layout(linked_symbols,
            retired_clock=manifest["retired_clock_conversion"])["end"]
        report["clock_conversion_pass"] = True
        report["wrong_radix_rejected"] = retired
        reports[name] = report
        (work / "results.json").write_text(json.dumps(reports, indent=2)+"\n")
        print(name, report["largest"], report["upper_free"], flush=True)
    control, retired = reports["control"], reports["retired"]
    assert retired["largest"]-control["largest"] == 128
    assert control["bios_low_bytes"]-retired["bios_low_bytes"] == retired["largest"]-control["largest"]
    assert retired["upper_free"] == control["upper_free"]
    assert retired["xms"] == control["xms"]
    fallback = {}
    for mode in ("HIGH", "LOW"):
        directory = work / f"fallback-{mode}"
        manifest = build(directory, early=True, tail_body=True, dispatch=True, characters=True,
            retire_characters=True, pack_headers=True, retire_media=True, pack_drive_graph=True,
            retire_clock=True, reservation_limit=0x10)
        clock = clock_probe(directory, manifest, False, True)
        disk = directory / "clock.img"
        shutil.copyfile(args.image, disk)
        install(disk, "IO.SYS", (directory / "IO.SYS").read_bytes())
        install(disk, "DOS/HIMEM.SYS", subprocess.check_output(
            ["mtype", "-i", str(ROOT / "out/floppy.img"), "::HIMEM.SYS"]))
        install(disk, "CONFIG.SYS", f"DEVICE=C:\\DOS\\HIMEM.SYS\r\nDOS={mode}\r\nBUFFERS=15\r\n".encode())
        install(disk, "AUTOEXEC.BAT", b"@ECHO OFF\r\nCLOCK.COM\r\n")
        install(disk, "CLOCK.COM", clock.read_bytes())
        run_clock(disk, directory)
        fallback[mode] = dict(image_sha256=sha(disk), active=False, clock_conversion_pass=True)
        (work / "fallback.json").write_text(json.dumps(fallback, indent=2)+"\n")
    print("PASS: clock owner retired, +128 conventional bytes, unchanged UMB/XMS", flush=True)


if __name__ == "__main__":
    main()
