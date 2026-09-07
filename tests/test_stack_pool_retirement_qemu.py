#!/usr/bin/env python3
"""Measure whole stack-pool placement in the pinned BIOS/shell/provider image."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from build_bios_low_image import ROOT, build
from capture_vc_memory_comparison import capture, image_file, parse_capture
from report_dos_bios_residency import parse_map
from test_dos_char_retirement_qemu import install
from test_umb_subpage_composition import xms_summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="packed BIOS/high-COMMAND composition before pool placement")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="stack-pool-retirement-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    assert image_file(args.image, "::MSDOS.SYS") == (ROOT / "src/DOS/MSDOS.SYS").read_bytes()
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
