#!/usr/bin/env python3
"""Build/poison the complete shell service and measure a supplied composition.

The input is a completed BIOS/provider image, not a newly rebuilt baseline.
Only COMMAND changes between the two fresh captures. This is not promotion.
Run make cmd_command first: the isolated normal build must match the native one.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from capture_vc_memory_comparison import capture, image_file, parse_capture, partition_offset
from report_command_residency import parse_map, check_relative_service_branches
from test_umb_subpage_composition import xms_summary

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "src/CMD/COMMAND"


def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_pipelines(work, floppy, env, modes=("HIGH", "LOW")):
    probe = work / "PIPEIO.COM"
    run(["nasm", "-f", "bin", ROOT / "tests/command_pipe_filter.asm", "-o", probe])
    for mode in modes:
        disk = work / f"pipeline-{mode}.img"
        shutil.copyfile(floppy, disk)
        for path, destination in ((probe, "::PIPEIO.COM"),
                                  (ROOT / "out/command-startup-qexit.com", "::QEXIT.COM")):
            run(["mcopy", "-o", "-i", disk, path, destination], env=env)
        config = f"DEVICE=A:\\HIMEM.SYS\r\nDOS={mode}\r\nBUFFERS=15\r\n"
        batch = ("@ECHO OFF\r\nCTTY AUX\r\n"
                 "ECHO PIPE_FIRST|PIPEIO|PIPEIO\r\n"
                 "ECHO PIPE_SECOND|PIPEIO\r\n"
                 "ECHO PIPE_THIRD|PIPEIO|PIPEIO|PIPEIO\r\n"
                 "COMMAND /C ECHO PIPE_CHILD|PIPEIO\r\n"
                 "ECHO PIPE_REDIRECT|PIPEIO|PIPEIO > PIPE1.OUT\r\n"
                 "ECHO PIPE_APPEND|PIPEIO|PIPEIO >> PIPE1.OUT\r\n"
                 "PIPEIO < PIPE1.OUT | PIPEIO > PIPE2.OUT\r\n"
                 "COMMAND /C ECHO PIPE_CHILD_RED|PIPEIO > PIPE3.OUT\r\n"
                 "ECHO PIPE_RELOAD_CONTINUED\r\nQEXIT.COM\r\n")
        for name, contents in (("CONFIG.SYS", config), ("AUTOEXEC.BAT", batch)):
            run(["mcopy", "-o", "-i", disk, "-", "::"+name],
                input=contents.encode("ascii"), env=env)
        before = set(run(["mdir", "-b", "-i", disk, "::"], env=env, capture_output=True).stdout.splitlines())
        with (work / f"pipeline-{mode}.log").open("w") as log:
            result = subprocess.run(["timeout", "40", "qemu-system-i386", "-display", "none",
                "-monitor", "none", "-cpu", "486", "-m", "8", "-boot", "a",
                "-drive", f"if=floppy,index=0,format=raw,file={disk}", "-serial", "stdio",
                "-no-reboot", "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
                stdout=log, stderr=log)
        assert result.returncode == 33, f"pipeline {mode}: emulator {result.returncode}"
        serial = (work / f"pipeline-{mode}.log").read_text()
        assert serial.count("PIPE_FILTER_OVERWRITE") == 14, serial
        for marker in ("PIPE_FIRST", "PIPE_SECOND", "PIPE_THIRD", "PIPE_CHILD", "PIPE_RELOAD_CONTINUED"):
            assert marker in serial.splitlines(), (mode, marker, serial)
        expected_outputs = (b"PIPE_REDIRECT\r\nPIPE_APPEND\r\n",
                            b"PIPE_REDIRECT\r\nPIPE_APPEND\r\n", b"PIPE_CHILD_RED\r\n")
        for index, expected in enumerate(expected_outputs, 1):
            output = run(["mtype", "-i", disk, f"::PIPE{index}.OUT"], env=env, capture_output=True).stdout
            assert output == expected, (mode, index, output)
        after = set(run(["mdir", "-b", "-i", disk, "::"], env=env, capture_output=True).stdout.splitlines())
        assert before <= after, before-after
        assert after-before == {b"::/PIPE1.OUT", b"::/PIPE2.OUT", b"::/PIPE3.OUT"}, after-before


def check_entry_mutation(work, high, floppy, env, symbols):
    # Force a wrong owner without moving any entry/branch. Merely dropping the
    # CS prefix can accidentally work when incoming DS happens to be transient.
    negative = work / "negative-owner"
    negative.mkdir()
    mutated = bytearray(high.read_bytes())
    entry = symbols["TCOMMAND"]-0x100
    assert mutated[entry:entry+3] == b"\x2e\x8e\x1e"
    mutated[entry:entry+5] = b"\x31\xc0\x8e\xd8\x90"  # XOR AX,AX; MOV DS,AX; NOP
    broken_command = negative / "COMMAND.COM"
    broken_command.write_bytes(mutated)
    broken_floppy = negative / "boot.img"
    shutil.copyfile(floppy, broken_floppy)
    run(["mcopy", "-o", "-i", broken_floppy, broken_command, "::COMMAND.COM"], env=env)
    try:
        check_pipelines(negative, broken_floppy, env, modes=("HIGH",))
    except AssertionError as error:
        assert (str(error) == "pipeline HIGH: emulator 124"
                or "PIPE_FILTER_OVERWRITE" in str(error)), str(error)
    else:
        raise AssertionError("wrong-DS TCOMMAND mutation was not detected")


def build(work, high):
    work.mkdir()
    for path in SOURCE.glob("*.OBJ"):
        shutil.copyfile(path, work / path.name)
    shutil.copyfile(SOURCE / "COMMAND.LNK", work / "COMMAND.LNK")
    defines = ("-DCOMMAND_RESIDENT_BINDING -DCOMMAND_HIGH_RESIDENT "
               "-DCOMMAND_HIGH_RESIDENT_POISON") if high else ""
    with (work / "build.log").open("w") as log:
        for module in ("COMMAND1", "COMMAND2", "RUCODE", "RDATA", "INIT", "TCMD2B", "TMISC1", "TPIPE", "TDATA", "TCODE"):
            run([ROOT / "bin/jwasm-masm",
                 f"-Mx -t {defines} -I. -I../../INC -I../../DOS -Fl={work / module}.LST",
                 f"{module}.ASM,{work / module}.OBJ;"], cwd=SOURCE, stdout=log, stderr=log)
        run([ROOT / "bin/wlink", "@COMMAND.LNK"], cwd=work, stdout=log, stderr=log)
        run([ROOT / "bin/exe2bin", "COMMAND.EXE COMMAND.COM"], cwd=work, stdout=log, stderr=log)
    return work / "COMMAND.COM"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="completed composed hard-disk image")
    parser.add_argument("--floppy", type=Path, default=ROOT / "out/floppy.img")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="command-high-retirement-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    (work / "emulator.txt").write_bytes(run(["qemu-system-i386", "--version"], capture_output=True).stdout)
    normal = build(work / "normal", False)
    high = build(work / "high", True)
    assert normal.read_bytes() == (SOURCE / "COMMAND.COM").read_bytes(), "default binary changed"
    for name, command in (("normal", normal), ("high", high)):
        _, entry_symbols = parse_map(work / name / "COMMAND.MAP")
        entry = entry_symbols["TCOMMAND"] - 0x100
        assert command.read_bytes()[entry:entry+3] == b"\x2e\x8e\x1e", "TCOMMAND must select resident DS through CS"
    segments, symbols = parse_map(work / "high/COMMAND.MAP")
    notice = (b"MS DOS Version 6.22 (C)Copyright 1988 Microsoft Corp"
              b"Licensed Material - Property of Microsoft  ")
    copyright_start, copyright_end = (symbols["resident_copyright_start"],
                                      symbols["resident_copyright_end"])
    assert segments["MSGOPT"].start <= copyright_start < copyright_end <= segments["MSGOPT"].end
    assert high.read_bytes()[copyright_start-0x100:copyright_end-0x100] == notice
    assert high.read_bytes().count(notice) == normal.read_bytes().count(notice)
    assert notice not in high.read_bytes()[:segments["HMACODE"].end-0x100]
    start, end = symbols["shell_service_start"], symbols["RES_CODE_END"]
    assert segments["DATARES"].end == start
    assert segments["SHELLCODE"].start == start and segments["SHELLCODE"].end == end
    assert segments["HMACODE"].start == end
    body = high.read_bytes()[start - 0x100:end - 0x100]
    decoded = run(["ndisasm", "-b16", f"-o{start}", "-"], input=body, capture_output=True)
    (work / "service.dis").write_bytes(decoded.stdout)
    check_relative_service_branches(decoded.stdout.decode(), start, end)
    gates = sorted((value, name) for name, value in symbols.items()
                   if name.startswith("shell_gate_") and name.endswith("_segment"))
    binary = high.read_bytes()
    targets = [(segment, int.from_bytes(binary[segment-0x102:segment-0x100], "little"))
               for segment, _ in gates]
    assert len(targets) == 13
    constants = ["%define EXPECT_WHOLE_SHELL 1",
                 f"%define SHELL_HIGH_ACTIVE {symbols['shell_high_active']}",
                 f"%define SHELL_HIGH_FIRST_SEG {targets[0][0]}",
                 f"%define SHELL_HIGH_FIRST_TARGET {targets[0][1]}",
                 f"%define SHELL_HIGH_LOW_PARAGRAPHS {(symbols['resident_catalog_start']+15)//16}",
                 "%macro SHELL_HIGH_CHECK_GATES 0"]
    for segment, target in targets:
        constants.extend((f"cmp word [es:{segment}],dx", "jne fail", "mov cx,ax",
                          f"add cx,{target}", f"cmp word [es:{segment-2}],cx", "jne fail"))
    pipe_delta = start - (segments["DATARES"].end-symbols["resident_catalog_start"]
                          +segments["HMACODE"].size)
    constants.extend((f"cmp word [es:{symbols['PIPESEG']}],dx", "jne fail",
                      "%if EXPECT_HMA", "mov cx,ax", f"add cx,{pipe_delta}",
                      "%else", f"mov cx,{symbols['PIPESTR']}", "%endif",
                      f"cmp word [es:{symbols['PIPEBASE']}],cx", "jne fail"))
    constants.append("%endmacro")
    gate_include = work / "high-gates.inc"
    gate_include.write_text("\n".join(constants)+"\n")
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
    floppy = work / "boot.img"
    shutil.copyfile(args.floppy, floppy)
    run(["mcopy", "-o", "-i", floppy, high, "::COMMAND.COM"], env=env)
    for mode in ("HIGH", "LOW"):
        with (work / f"startup-{mode}.log").open("w") as log:
            run(["bash", ROOT / "tests/test_command_startup_qemu.sh"],
                env=dict(env, FLOPPY_IMAGE=str(floppy), COMMAND_CRITICAL_ABI="1",
                         COMMAND_CRITICAL_DOS_MODE=mode), stdout=log, stderr=log)
        shutil.copyfile(ROOT / "out/command-fail-serial.log", work / f"critical-{mode}.log")
    with (work / "int2e.log").open("w") as log:
        run(["bash", ROOT / "tests/test_command_int2e_owner_qemu.sh"],
            env=dict(env, FLOPPY_IMAGE=str(args.floppy.resolve()), COMMAND_IMAGE=str(high),
                     COMMAND_GATE_INCLUDE=str(gate_include)),
            stdout=log, stderr=log)
    with (work / "loadhigh.log").open("w") as log:
        run(["bash", ROOT / "tests/test_loadhigh_qemu.sh"],
            env=dict(env, FLOPPY_IMAGE=str(floppy)), stdout=log, stderr=log)
    for name in ("provider", "regions", "fallback", "high"):
        shutil.copyfile(ROOT / f"out/loadhigh-{name}.log", work / f"loadhigh-{name}.log")
    check_pipelines(work, floppy, env)
    check_entry_mutation(work, high, floppy, env, symbols)
    probe = work / "CEILING.COM"
    run(["nasm", "-f", "bin", ROOT / "tests/memory_ceiling_probe.asm", "-o", probe])
    results = {}
    inputs = {}
    for name, command in (("normal", normal), ("high", high)):
        disk = work / f"input-{name}.img"
        shutil.copyfile(args.image, disk)
        spec = f"{disk}@@{partition_offset(disk)}"
        for destination in ("::COMMAND.COM", "::DOS/COMMAND.COM"):
            run(["mcopy", "-o", "-i", spec, command, destination], env=env)
            assert image_file(disk, destination) == command.read_bytes()
        for unchanged in ("::CONFIG.SYS", "::AUTOEXEC.BAT", "::IO.SYS", "::MSDOS.SYS",
                          "::DOS/HIMEM.SYS", "::DOS/EMM386.EXE", "::VC/VC.COM"):
            assert image_file(disk, unchanged) == image_file(args.image, unchanged)
        inputs[name] = sha(disk)
        serial, screen = capture(name, disk, work, probe)
        results[name] = parse_capture(serial, screen)
        results[name]["xms"] = xms_summary(serial.read_text(encoding="latin-1"))
        print(f"Captured {name}: {results[name]['largest']} conventional, "
              f"{results[name]['upper_free']} UMB", flush=True)
    (work / "results.json").write_text(json.dumps(dict(
        source_image_sha256=sha(args.image), input_sha256=inputs,
        command_sha256={"normal": sha(normal), "high": sha(high)},
        command_hma_bytes=(segments["DATARES"].end-symbols["resident_catalog_start"]
                           +segments["HMACODE"].size+end-start),
        service_bytes=end-start, low_break=(symbols["resident_catalog_start"]+15)&~15,
        results=results), indent=2)+"\n")
    assert results["high"]["largest"] > results["normal"]["largest"]
    _, normal_symbols = parse_map(work / "normal/COMMAND.MAP")
    normal_low = (normal_symbols["resident_catalog_start"]+15)&~15
    high_low = (symbols["resident_catalog_start"]+15)&~15
    assert results["high"]["largest"] - results["normal"]["largest"] == normal_low - high_low
    assert results["high"]["upper_free"] == results["normal"]["upper_free"]
    assert results["high"]["xms"] == results["normal"]["xms"]
    print("PASS: poisoned service retirement produces a composed gain without UMB/XMS cost", flush=True)


if __name__ == "__main__":
    main()
