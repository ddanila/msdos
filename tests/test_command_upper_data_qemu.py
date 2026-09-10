#!/usr/bin/env python3
"""Measure complete COMMAND data retirement, not a routing-only build."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from capture_vc_memory_comparison import ROOT, capture, image_file, parse_capture
from test_command_high_resident_qemu import build
from test_dos_char_retirement_qemu import install
from test_umb_subpage_composition import xms_summary


def check_runtime(work, candidate, *, initial_commands="", extra_commands=""):
    """Exercise the upper owner in the actual manager/BIOS composition."""
    disk = work / "runtime.img"
    shutil.copyfile(candidate, disk)
    probe = work / "PIPEIO.COM"
    subprocess.run(["nasm", "-f", "bin", ROOT / "tests/command_pipe_filter.asm",
                    "-o", probe], check=True)
    install(disk, "PIPEIO.COM", probe.read_bytes())
    exit_probe = work / "QEXIT.COM"
    subprocess.run(["nasm", "-f", "bin", ROOT / "tests/qemu_exit.asm",
                    "-o", exit_probe], check=True)
    install(disk, "QEXIT.COM", exit_probe.read_bytes())
    batch = ("@ECHO OFF\r\nCTTY AUX\r\n" + initial_commands +
             "SET PACKED=ENVIRONMENT_SURVIVED\r\n"
             "SET COMSPEC=C:\\DOS\\COMMAND.COM\r\n"
             "ECHO PIPE_FIRST|PIPEIO|PIPEIO\r\n"
             "ECHO PIPE_SECOND|PIPEIO\r\n"
             "ECHO PIPE_THIRD|PIPEIO|PIPEIO|PIPEIO\r\n"
             "COMMAND /C ECHO PIPE_CHILD|PIPEIO\r\n"
             "ECHO PIPE_REDIRECT|PIPEIO|PIPEIO > PIPE1.OUT\r\n"
             "ECHO PIPE_APPEND|PIPEIO|PIPEIO >> PIPE1.OUT\r\n"
             "PIPEIO < PIPE1.OUT | PIPEIO > PIPE2.OUT\r\n"
             "COMMAND /C ECHO PIPE_CHILD_RED|PIPEIO > PIPE3.OUT\r\n"
             "ECHO %PACKED%\r\nECHO PIPE_RELOAD_CONTINUED\r\n" + extra_commands + "QEXIT.COM\r\n")
    install(disk, "AUTOEXEC.BAT", batch.encode("ascii"))
    with (work / "runtime.log").open("wb") as log:
        result = subprocess.run(["qemu-system-i386", "-display", "none", "-monitor", "none",
            "-cpu", "486", "-m", "8", "-boot", "c", "-serial", "stdio", "-no-reboot",
            "-drive", f"if=ide,index=0,format=raw,file={disk}",
            "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
            stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, timeout=45)
    serial = (work / "runtime.log").read_text(encoding="latin-1")
    assert result.returncode == 33, (result.returncode, serial)
    assert serial.count("PIPE_FILTER_OVERWRITE") == 14, serial
    for marker in ("PIPE_FIRST", "PIPE_SECOND", "PIPE_THIRD", "PIPE_CHILD",
                   "ENVIRONMENT_SURVIVED", "PIPE_RELOAD_CONTINUED"):
        assert marker in serial.splitlines(), (marker, serial)
    for name, expected in (("PIPE1.OUT", b"PIPE_REDIRECT\r\nPIPE_APPEND\r\n"),
                           ("PIPE2.OUT", b"PIPE_REDIRECT\r\nPIPE_APPEND\r\n"),
                           ("PIPE3.OUT", b"PIPE_CHILD_RED\r\n")):
        assert image_file(disk, "::" + name) == expected, name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--binary", type=Path, help="reuse an already built upper-data COMMAND")
    parser.add_argument("--minimum-gain", type=int, default=336,
                        help="required largest-block gain against the selected input (112 for stack retirement)")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="command-upper-data-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    binary = args.binary or build(work / "upper", True, upper_data=True)
    candidate = work / "input.img"
    shutil.copyfile(args.image, candidate)
    for name in ("COMMAND.COM", "DOS/COMMAND.COM"):
        install(candidate, name, binary.read_bytes())
    unchanged = {}
    for name in ("IO.SYS", "MSDOS.SYS", "CONFIG.SYS", "AUTOEXEC.BAT",
                 "DOS/HIMEM.SYS", "DOS/EMM386.EXE", "VC/VC.COM"):
        data = image_file(args.image, "::" + name)
        assert data == image_file(candidate, "::" + name), name
        unchanged[name] = hashlib.sha256(data).hexdigest()
    ceiling = work / "CEILING.COM"
    subprocess.run(["nasm", "-f", "bin", ROOT / "tests/memory_ceiling_probe.asm",
                    "-o", ceiling], check=True)
    results = dict(unchanged_sha256=unchanged,
                   command_sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
    command_map = binary.with_suffix(".MAP")
    if command_map.exists():
        shutil.copyfile(command_map, work / "COMMAND.MAP")
    # Candidate first: a broken retirement must not trigger another control run.
    for name, disk in (("after", candidate), ("before", args.image)):
        serial, screen = capture(name, disk.resolve(), work, ceiling)
        results[name] = parse_capture(serial, screen)
        results[name]["xms"] = xms_summary(serial.read_text(encoding="latin-1"))
        print(f"{name}: {results[name]}", flush=True)
        (work / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    # Retirement must extend the largest block, not leave released bytes
    # trapped in an arena hole. Keep the selected comparison explicit.
    gain = results["after"]["largest"] - results["before"]["largest"]
    results["minimum_gain"] = args.minimum_gain
    assert args.minimum_gain > 0
    assert gain >= args.minimum_gain, f"incomplete COMMAND packing: largest-block gain {gain}, need {args.minimum_gain}"
    # MEM lists MCB segments: the reserved region starts one paragraph below
    # the reported conventional ceiling, even when EBDA makes it less than A000.
    conventional = [row for row in results["after"]["mem_rows"]
                    if row["segment"] < results["after"]["ceiling"] - 1]
    first_free = next(i for i, row in enumerate(conventional) if row["type"] == "Free")
    assert all(row["type"] == "Free" for row in conventional[first_free:]), "stranded low hole"
    assert results["after"]["upper_free"] >= 47888
    assert results["after"]["xms"] is not None
    assert results["after"]["xms"] == results["before"]["xms"]
    check_runtime(work, candidate)
    results["runtime_passed"] = True
    (work / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
