#!/usr/bin/env python3
"""Build/poison the complete shell service and measure a supplied composition.

The input is a completed BIOS/provider image, not a newly rebuilt baseline.
Only COMMAND changes between the two fresh captures. This is not promotion.
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


def build(work, high):
    work.mkdir()
    for path in SOURCE.glob("*.OBJ"):
        shutil.copyfile(path, work / path.name)
    shutil.copyfile(SOURCE / "COMMAND.LNK", work / "COMMAND.LNK")
    defines = ("-DCOMMAND_RESIDENT_BINDING -DCOMMAND_HIGH_RESIDENT "
               "-DCOMMAND_HIGH_RESIDENT_POISON") if high else ""
    with (work / "build.log").open("w") as log:
        for module in ("COMMAND1", "COMMAND2", "RUCODE", "RDATA", "INIT", "TCMD2B"):
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
    segments, symbols = parse_map(work / "high/COMMAND.MAP")
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
    assert results["high"]["upper_free"] == results["normal"]["upper_free"]
    assert results["high"]["xms"] == results["normal"]["xms"]
    print("PASS: poisoned service retirement produces a composed gain without UMB/XMS cost", flush=True)


if __name__ == "__main__":
    main()
