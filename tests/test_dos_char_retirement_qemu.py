#!/usr/bin/env python3
"""Qualify CharType retirement against a frozen, fully composed DOS-high image."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from build_bios_low_image import build
from capture_vc_memory_comparison import capture, image_file, parse_capture, partition_offset
from report_dos_bios_residency import parse_map, rounded
from test_umb_subpage_composition import xms_summary

ROOT = Path(__file__).resolve().parents[1]
ENV = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")


def install(image, name, data):
    subprocess.run(["mcopy", "-o", "-i", f"{image}@@{partition_offset(image)}",
                    "-", "::" + name], input=data, env=ENV, check=True)
    assert image_file(image, "::" + name) == data


def probe(work, source, name, mode, kernel=None, bios=None, before=b""):
    image = work / f"fcb-{name}.img"
    shutil.copyfile(source, image)
    config = image_file(image, "::CONFIG.SYS")
    assert b"DOS=HIGH" in config
    if mode == "LOW":
        # Standalone low-kernel qualification, not paired-provider fallback.
        config = b"DOS=LOW\r\nFILES=30\r\nBUFFERS=15\r\nLASTDRIVE=Z\r\n"
    install(image, "CONFIG.SYS", config)
    if kernel is not None:
        install(image, "MSDOS.SYS", kernel)
    if bios is not None:
        install(image, "IO.SYS", bios)
    install(image, "I21FCB.COM", (work / "I21FCB.COM").read_bytes())
    install(image, "QEXIT.COM", (work / "QEXIT.COM").read_bytes())
    install(image, "AUTOEXEC.BAT", b"@ECHO OFF\r\nCTTY AUX\r\n" + before + b"I21FCB.COM\r\nQEXIT.COM\r\n")
    result = subprocess.run([
        "qemu-system-i386", "-display", "none", "-monitor", "none",
        "-machine", "pc", "-cpu", "486", "-m", "8",
        "-drive", f"if=ide,index=0,format=raw,file={image},cache=writethrough",
        "-boot", "c", "-serial", "stdio", "-no-reboot",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=40)
    (work / f"fcb-{name}.log").write_bytes(result.stdout)
    passed = b"INT21_FCB_PASS" in result.stdout
    if passed:
        assert result.returncode == 33
    print(f"FCB {name}: exit={result.returncode}, pass={passed}", flush=True)
    return passed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="completed pre-retirement composed image")
    parser.add_argument("old_map", type=Path, help="kernel map matching that image")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="dos-char-retirement-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    old = image_file(args.image, "::MSDOS.SYS")
    new = (ROOT / "src/DOS/MSDOS.SYS").read_bytes()
    _, before = parse_map(args.old_map)
    segments, after = parse_map(ROOT / "src/DOS/MSDOS.MAP")
    assert before["SYSBUF"] == after["SYSBUF"]
    assert rounded(before["DOS_LOW_GATE_END"]) - rounded(after["DOS_LOW_GATE_END"]) == 256
    assert before["FCB001E"] <= before["DOS_LOW_GATE_END"]
    high = segments["HIGH_TABLE"]
    assert high.paragraph * 16 + high.offset <= after["FCB001S"] < after["FCB001E"] <= after["SYSBUF"]
    assert after["FCB001E"] - after["FCB001S"] == 256
    assert old[before["FCB001S"]:before["FCB001E"]] == new[after["FCB001S"]:after["FCB001E"]]
    shutil.copyfile(args.old_map, work / "old-MSDOS.MAP")
    shutil.copyfile(ROOT / "src/DOS/MSDOS.MAP", work / "MSDOS.MAP")
    (work / "old-MSDOS.SYS").write_bytes(old)
    (work / "MSDOS.SYS").write_bytes(new)
    provider = work / "EMM386.EXE"
    provider.write_bytes(image_file(args.image, "::DOS/EMM386.EXE"))
    build(work / "bios", early=True, tail_body=True, rebase=True, compact=True,
          high_cds=True, dispatch=True, characters=True, retire_characters=True,
          pack_headers=True, retire_media=True, paired_provider=provider)
    candidate = work / "input-new.img"
    shutil.copyfile(args.image, candidate)
    install(candidate, "IO.SYS", (work / "bios/IO.SYS").read_bytes())
    install(candidate, "MSDOS.SYS", new)
    unchanged = {}
    for name in ("CONFIG.SYS", "AUTOEXEC.BAT", "COMMAND.COM", "DOS/COMMAND.COM",
                 "DOS/HIMEM.SYS", "DOS/EMM386.EXE", "VC/VC.COM"):
        data = image_file(args.image, "::" + name)
        assert image_file(candidate, "::" + name) == data
        unchanged[name] = hashlib.sha256(data).hexdigest()
    for source, target in (("int21_fcb_probe.asm", "I21FCB.COM"),
                           ("qemu_exit.asm", "QEXIT.COM"),
                           ("memory_ceiling_probe.asm", "CEILING.COM")):
        subprocess.run(["nasm", "-f", "bin", ROOT / "tests" / source,
                        "-o", work / target], check=True)
    assert probe(work, candidate, "high", "HIGH")
    # Qualify the standalone kernel's DOS-low path separately. The experimental
    # paired provider exits before the probe with DOS=LOW; its fallback remains
    # outside this focused table-retirement qualification.
    build(work / "bios-low")
    assert probe(work, candidate, "low", "LOW", bios=(work / "bios-low/IO.SYS").read_bytes())
    # Decode the linked routine, selecting instruction boundaries, not a byte
    # pattern that could also occur inside an operand or embedded data.
    routine = new[after["TransFCB"]:after["TextFromDrive"]]
    decoded = subprocess.check_output(["ndisasm", "-b", "16", "-"], input=routine).decode()
    (work / "transfcb.dis").write_text(decoded)
    sites = [int(line.split()[0], 16) + after["TransFCB"]
             for line in decoded.splitlines() if "cs xlatb" in line]
    assert len(sites) == 1, sites  # Native non-DBCS build.
    bad = bytearray(new)
    assert bad[sites[0]:sites[0] + 2] == b"\x2e\xd7"
    bad[sites[0]] = 0x26  # Restore the obsolete ES owner, without changing size.
    assert not probe(work, candidate, "wrong-selector", "HIGH", bytes(bad))
    assert b"INT21_16_FAIL" in (work / "fcb-wrong-selector.log").read_bytes()
    results = {}
    for name, image in (("old", args.image), ("new", candidate)):
        serial, screen = capture(name, image.resolve(), work, work / "CEILING.COM")
        results[name] = parse_capture(serial, screen)
        results[name]["xms"] = xms_summary(serial.read_text(encoding="latin-1"))
        print(f"Measured {name}: {results[name]['largest']} conventional, "
              f"{results[name]['upper_free']} UMB, {results[name]['xms']} XMS", flush=True)
    assert results["new"]["largest"] - results["old"]["largest"] == 256
    assert results["new"]["upper_free"] == results["old"]["upper_free"]
    assert results["new"]["xms"] is not None
    assert results["new"]["xms"] == results["old"]["xms"]
    (work / "results.json").write_text(json.dumps(dict(
        results=results, unchanged_sha256=unchanged, selector_site=sites[0],
        input_sha256={"old": hashlib.sha256(args.image.read_bytes()).hexdigest(),
                      "new": hashlib.sha256(candidate.read_bytes()).hexdigest()}), indent=2) + "\n")
    print("PASS: complete CharType retirement; composed gain 256 bytes, no UMB/XMS cost", flush=True)


if __name__ == "__main__":
    main()
