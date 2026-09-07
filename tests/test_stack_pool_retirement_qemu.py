#!/usr/bin/env python3
"""Measure whole stack-pool placement in the pinned BIOS/shell/provider image."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile

from build_bios_low_image import ROOT, build
from capture_vc_memory_comparison import capture, image_file, parse_capture
from report_dos_bios_residency import parse_map
from test_dos_char_retirement_qemu import install
from test_umb_subpage_composition import xms_summary


def shape_checks(source, bios, work, controlled=False):
    """Use frozen composed binaries, changing only STACKS and probe startup."""
    assert image_file(source, "::IO.SYS") == (bios / "IO.SYS").read_bytes()
    manifest = json.loads((bios / "low.json").read_text())
    enabled = manifest["high_stack_pool"] and not manifest["fail_stack_pool"]
    segments, symbols = parse_map(bios / "msBIO.map")
    init = segments["SYSINITSEG"].paragraph * 16 + segments["SYSINITSEG"].offset
    symbols = {k.upper(): v - init for k, v in symbols.items()}
    assert symbols["ENDSTACKCODE"] == 0x259
    config = image_file(source, "::CONFIG.SYS")
    assert b"DOS=HIGH" in config.upper()
    results = {}
    # The pinned topology has no 33,280-byte UMB: the maximum pool must fall
    # back intact. The other pools fit without changing configured resources.
    for count, size, upper in ((8, 32, True), (9, 128, True), (8, 512, True),
                               (64, 32, True), (64, 128, True), (64, 512, False)):
        if controlled and size != 32:
            continue
        upper = upper and enabled
        name = f"{count}-{size}"
        directory = work / name
        directory.mkdir()
        (directory / "stack-defs.inc").write_text(
            f"%define EXPECT_UPPER {int(upper)}\n%define EXPECT_DOS_HIGH 1\n"
            "%define STACK_SHAPE_TRACE 1\n"
            f"%define STACK_COUNT {count}\n%define STACK_SIZE {size}\n"
            f"%define ENTRY_OFFSET {symbols['INT08']}\n%define OLD_SLOT {symbols['OLD08']}\n"
            + ("%define POOL_CONTROLLED_RESEED 1\n" if controlled else ""))
        image = directory / "probe.img"
        shutil.copyfile(source, image)
        updated, replacements = re.subn(rb"(?im)^STACKS=[^\r\n]*", f"STACKS={count},{size}".encode(), config)
        assert replacements <= 1
        if not replacements:
            updated = config.rstrip(b"\r\n") + f"\r\nSTACKS={count},{size}\r\n".encode()
        install(image, "CONFIG.SYS", updated)
        for asm, target in (("stack_pool_probe.asm", "STACKCHK.COM"),
                            ("int21_fcb_probe.asm", "I21FCB.COM"), ("qemu_exit.asm", "QEXIT.COM")):
            subprocess.run(["nasm", "-f", "bin", "-DNO_DEBUG_EXIT=1", f"-I{directory}/",
                ROOT / "tests" / asm, "-o", directory / target], check=True)
            install(image, target, (directory / target).read_bytes())
        install(image, "AUTOEXEC.BAT", b"@ECHO OFF\r\nCTTY AUX\r\nSTACKCHK.COM\r\n"
                b"I21FCB.COM\r\nSTACKCHK.COM\r\nQEXIT.COM\r\n")
        result = subprocess.run(["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
            "-display", "none", "-monitor", "none", "-serial", "stdio", "-no-reboot", "-boot", "c",
            "-debugcon", f"file:{directory / 'debug.log'}", "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
            "-drive", f"if=ide,index=0,format=raw,file={image},cache=writethrough"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=40)
        (directory / "probe.log").write_bytes(result.stdout)
        debug = (directory / "debug.log").read_bytes()
        passed = (result.returncode == 33 and debug.count(b"STACK_POOL_NESTED_PASS") == 2
                  and b"STACK_POOL_FAIL" not in debug and b"INT21_FCB_PASS" in result.stdout)
        passed = passed and debug.count(b"STACK_POOL_CONTROLLED_RESEED") == (2 if controlled else 0)
        results[name] = dict(count=count, size=size, upper=upper, passed=passed, exit_code=result.returncode,
            controlled_marker_repair=controlled,
            pool_bytes=(count*(size+8)+15)//16*16, nested_visits=count if passed else None,
            image_sha256=hashlib.sha256(image.read_bytes()).hexdigest())
        scope = "controlled marker repair" if controlled else "unmodified markers"
        print(f"{'PASS' if passed else 'FAIL'} STACKS={count},{size}: {scope}, expected {'upper' if upper else 'low'}, artifacts {directory}", flush=True)
    (work / "shapes.json").write_text(json.dumps(dict(results=results,
        source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        bios_sha256=hashlib.sha256((bios / "IO.SYS").read_bytes()).hexdigest()), indent=2) + "\n")
    assert all(row["passed"] for row in results.values()), work / "shapes.json"


def fallback_checks(source, work):
    """Standalone managers: do not confuse these with paired-provider DOS-low."""
    directory = work / "fallback"
    build(directory, early=True, tail_body=True, rebase=True, compact=True,
          dispatch=True, characters=True, retire_characters=True, pack_headers=True,
          retire_media=True, pack_drive_graph=True, high_stack_pool=True)
    segments, symbols = parse_map(directory / "msBIO.map")
    init = segments["SYSINITSEG"].paragraph * 16 + segments["SYSINITSEG"].offset
    symbols = {k.upper(): v - init for k, v in symbols.items()}
    (directory / "stack-defs.inc").write_text(
        f"%define EXPECT_UPPER 0\n%define ENTRY_OFFSET {symbols['INT08']}\n"
        f"%define OLD_SLOT {symbols['OLD08']}\n")
    for asm, target in (("int21_fcb_probe.asm", "I21FCB.COM"), ("qemu_exit.asm", "QEXIT.COM")):
        subprocess.run(["nasm", "-f", "bin", "-DNO_DEBUG_EXIT=1", f"-I{directory}/",
                        ROOT / "tests" / asm, "-o", directory / target], check=True)
    # Use the standalone deployment driver, not the pinned paired-provider HIMEM.
    himem = subprocess.check_output(["mtype", "-i", ROOT / "out/floppy.img", "::HIMEM.SYS"],
                                    env=dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1"))
    emm = subprocess.check_output(["mtype", "-i", ROOT / "out/floppy.img", "::EMM386.EXE"],
                                  env=dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1"))
    results = {}
    for name, manager, dos in (("bare-low", False, "LOW"), ("himem-low", True, "LOW"),
                               ("himem-high-no-umb", True, "HIGH"), ("emm-low", True, "LOW")):
        image = directory / f"{name}.img"
        shutil.copyfile(source, image)
        install(image, "IO.SYS", (directory / "IO.SYS").read_bytes())
        install(image, "DOS/HIMEM.SYS", himem)
        install(image, "DOS/EMM386.EXE", emm)
        config = ((b"DEVICE=C:\\DOS\\HIMEM.SYS /TESTMEM:OFF\r\n" if manager else b"")
                  + (b"DEVICE=C:\\DOS\\EMM386.EXE RAM\r\n" if name == "emm-low" else b"")
                  + f"DOS={dos},UMB\r\nFILES=20\r\nBUFFERS=15\r\nLASTDRIVE=Z\r\nSTACKS=9,128\r\n".encode())
        install(image, "CONFIG.SYS", config)
        subprocess.run(["nasm", "-f", "bin", f"-DEXPECT_DOS_HIGH={int(dos == 'HIGH')}",
                        f"-I{directory}/", ROOT / "tests/stack_pool_probe.asm",
                        "-o", directory / "STACKCHK.COM"], check=True)
        for target in ("STACKCHK.COM", "I21FCB.COM", "QEXIT.COM"):
            install(image, target, (directory / target).read_bytes())
        install(image, "AUTOEXEC.BAT", b"@ECHO OFF\r\nCTTY AUX\r\nSTACKCHK.COM\r\n"
                b"I21FCB.COM\r\nSTACKCHK.COM\r\nQEXIT.COM\r\n")
        debug_path = directory / f"{name}-debug.log"
        result = subprocess.run(["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
            "-display", "none", "-monitor", "none", "-serial", "stdio", "-no-reboot", "-boot", "c",
            "-debugcon", f"file:{debug_path}", "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
            "-drive", f"if=ide,index=0,format=raw,file={image},cache=writethrough"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=40)
        (directory / f"{name}.log").write_bytes(result.stdout)
        debug = debug_path.read_bytes()
        assert result.returncode == 33, (name, result.returncode, debug)
        assert debug.count(b"STACK_POOL_NESTED_PASS") == 2 and b"STACK_POOL_FAIL" not in debug
        assert b"INT21_FCB_PASS" in result.stdout
        results[name] = dict(config=config.decode(), image_sha256=hashlib.sha256(image.read_bytes()).hexdigest())
        print(f"PASS {name}: complete low pool and nested switches before/after I/O", flush=True)
    (directory / "results.json").write_text(json.dumps(dict(results=results,
        source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        bios_sha256=hashlib.sha256((directory / "IO.SYS").read_bytes()).hexdigest(),
        himem_sha256=hashlib.sha256(himem).hexdigest(),
        emm_sha256=hashlib.sha256(emm).hexdigest()), indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="packed BIOS/high-COMMAND composition before pool placement")
    parser.add_argument("--fallback-only", action="store_true", help="qualify standalone DOS-low and absent-UMB paths")
    parser.add_argument("--shapes-bios", type=Path, help="qualify STACKS bounds using this matching frozen BIOS build")
    parser.add_argument("--controlled-stacks", action="store_true", help="diagnostic 32-byte handler test after explicit marker repair; not boot qualification")
    args = parser.parse_args()
    if args.fallback_only and args.shapes_bios:
        parser.error("choose fallback or shape qualification")
    if args.controlled_stacks and not args.shapes_bios:
        parser.error("--controlled-stacks requires --shapes-bios")
    work = Path(tempfile.mkdtemp(prefix="stack-pool-retirement-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    assert image_file(args.image, "::MSDOS.SYS") == (ROOT / "src/DOS/MSDOS.SYS").read_bytes()
    if args.shapes_bios:
        shape_checks(args.image, args.shapes_bios, work, args.controlled_stacks)
        return
    if args.fallback_only:
        fallback_checks(args.image, work)
        return
    provider = work / "EMM386.EXE"
    provider.write_bytes(image_file(args.image, "::DOS/EMM386.EXE"))
    options = dict(early=True, tail_body=True, rebase=True, compact=True,
                   high_cds=True, dispatch=True, characters=True, retire_characters=True,
                   pack_headers=True, retire_media=True, pack_drive_graph=True, paired_provider=provider)
    images, manifests, unchanged = {}, {}, {}
    for name, upper, reject in (("control", False, False), ("upper", True, False),
                                ("rejected", True, True)):
        directory = work / name
        manifests[name] = build(directory, high_stack_pool=upper, fail_stack_pool=reject, **options)
        binary = (directory / "IO.SYS").read_bytes()
        if name == "control":
            assert binary == image_file(args.image, "::IO.SYS")
        image = work / f"input-{name}.img"
        shutil.copyfile(args.image, image)
        install(image, "IO.SYS", binary)
        images[name] = image
        for path in ("MSDOS.SYS", "COMMAND.COM", "DOS/COMMAND.COM", "CONFIG.SYS", "AUTOEXEC.BAT",
                     "DOS/HIMEM.SYS", "DOS/EMM386.EXE", "VC/VC.COM"):
            data = image_file(args.image, "::" + path)
            assert image_file(image, "::" + path) == data
            unchanged[path] = hashlib.sha256(data).hexdigest()
        segments, symbols = parse_map(directory / "msBIO.map")
        init = segments["SYSINITSEG"]
        symbols = {k.upper(): v - (init.paragraph * 16 + init.offset) for k, v in symbols.items()}
        assert symbols["ENDSTACKCODE"] == 0x259
        (directory / "stack-defs.inc").write_text(
            f"%define EXPECT_UPPER {int(upper and not reject)}\n"
            f"%define ENTRY_OFFSET {symbols['INT08']}\n%define OLD_SLOT {symbols['OLD08']}\n")
        for source, target in (("stack_pool_probe.asm", "STACKCHK.COM"),
                               ("int21_fcb_probe.asm", "I21FCB.COM"),
                               ("qemu_exit.asm", "QEXIT.COM")):
            subprocess.run(["nasm", "-f", "bin", "-DNO_DEBUG_EXIT=1", f"-I{directory}/", ROOT / "tests" / source,
                            "-o", directory / target], check=True)
        probe_image = directory / "probe.img"
        shutil.copyfile(image, probe_image)
        for target in ("STACKCHK.COM", "I21FCB.COM", "QEXIT.COM"):
            install(probe_image, target, (directory / target).read_bytes())
        install(probe_image, "AUTOEXEC.BAT", b"@ECHO OFF\r\nCTTY AUX\r\nECHO STACK_BEFORE_IO\r\nSTACKCHK.COM\r\n"
                b"I21FCB.COM\r\nECHO STACK_AFTER_IO\r\nSTACKCHK.COM\r\nECHO STACK_DONE\r\nQEXIT.COM\r\n")
        command = ["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
            "-display", "none", "-monitor", "none", "-serial", "stdio", "-no-reboot", "-boot", "c",
            "-debugcon", f"file:{directory / 'debug.log'}", "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
            "-drive", f"if=ide,index=0,format=raw,file={probe_image},cache=writethrough"]
        result = subprocess.run(command,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=40)
        (directory / "probe.log").write_bytes(result.stdout)
        debug = (directory / "debug.log").read_bytes()
        assert result.returncode == 33, (name, result.returncode, debug)
        assert debug.count(b"STACK_POOL_NESTED_PASS") == 2 and b"STACK_POOL_FAIL" not in debug
        assert b"INT21_FCB_PASS" in result.stdout
        print(f"PASS {name}: nine nested stack switches before/after FCB I/O", flush=True)
        if name == "upper":
            subprocess.run(["nasm", "-f", "bin", "-DPOOL_BAD_BACKLINK=1", f"-I{directory}/",
                ROOT / "tests/stack_pool_probe.asm", "-o", directory / "BADSTACK.COM"], check=True)
            install(probe_image, "STACKCHK.COM", (directory / "BADSTACK.COM").read_bytes())
            (directory / "good-debug.log").write_bytes(debug)
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=40)
            (directory / "negative.log").write_bytes(result.stdout)
            debug = (directory / "debug.log").read_bytes()
            assert result.returncode == 35 and b"STACK_POOL_BAD_BACKLINK_READY" in debug
            assert b"STACK_POOL_FAIL" in debug and b"STACK_POOL_NESTED_PASS" not in debug
            print("PASS upper negative: explicit corrupted-backlink rejection", flush=True)
    assert len({m["embedded_payload_bytes"] for m in manifests.values()}) == 1
    ceiling = work / "CEILING.COM"
    subprocess.run(["nasm", "-f", "bin", ROOT / "tests/memory_ceiling_probe.asm", "-o", ceiling], check=True)
    results = {}
    for name, image in images.items():
        serial, screen = capture(name, image, work, ceiling)
        results[name] = parse_capture(serial, screen)
        results[name]["xms"] = xms_summary(serial.read_text(encoding="latin-1"))
        print(f"Measured {name}: {results[name]['largest']} conventional / {results[name]['upper_free']} UMB", flush=True)
    assert results["upper"]["largest"] - results["control"]["largest"] == 1232
    assert results["control"]["upper_free"] - results["upper"]["upper_free"] == 1264
    assert results["upper"]["upper_free"] >= 47888
    for key in ("largest", "upper_free", "xms"):
        assert results["rejected"][key] == results["control"][key]
    assert results["upper"]["xms"] is not None and results["upper"]["xms"] == results["control"]["xms"]
    (work / "results.json").write_text(json.dumps(dict(results=results, unchanged_sha256=unchanged,
        input_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest()), indent=2) + "\n")
    print("PASS: whole stack pool releases 1,232 conventional bytes", flush=True)


if __name__ == "__main__":
    main()
