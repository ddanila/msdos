#!/usr/bin/env python3
"""Measure initial-SFT low-copy retirement in the complete paired layout."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from build_bios_low_image import ROOT, build
from capture_vc_memory_comparison import capture, image_file, parse_capture
from report_dos_bios_residency import parse_map, rounded
from test_dos_char_retirement_qemu import install, probe
from test_umb_subpage_composition import xms_summary


def qualify(work, candidate):
    """Public structure consumers and SHARE must survive the shifted prefix."""
    subprocess.run(["nasm", "-f", "bin", ROOT / "tests/internal_structures_probe.asm",
                    "-o", work / "INTERNAL.COM"], check=True)
    subprocess.run(["nasm", "-f", "bin", "-DREQUIRE_SHARE=1",
                    ROOT / "tests/int21_fcb_probe.asm", "-o", work / "I21FCB.COM"], check=True)
    for mode in ("HIGH", "LOW"):
        low_bios = (work / "bios-low/IO.SYS").read_bytes() if mode == "LOW" else None
        assert probe(work, candidate, f"share-{mode}", mode, bios=low_bios,
                     before=b"C:\\DOS\\SHARE /F:4096 /L:40\r\n")
        disk = work / f"structures-{mode}.img"
        shutil.copyfile(candidate, disk)
        if low_bios:
            install(disk, "IO.SYS", low_bios)
            install(disk, "CONFIG.SYS", b"DOS=LOW\r\nFILES=30\r\nBUFFERS=15\r\nLASTDRIVE=Z\r\n")
        install(disk, "INTERNAL.COM", (work / "INTERNAL.COM").read_bytes())
        install(disk, "AUTOEXEC.BAT", b"@ECHO OFF\r\nCTTY AUX\r\nINTERNAL.COM\r\n")
        result = subprocess.run([
            "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
            "-display", "none", "-monitor", "none", "-serial", "stdio", "-boot", "c",
            "-no-reboot", "-drive", f"if=ide,format=raw,file={disk}",
            "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
            capture_output=True, timeout=40)
        (work / f"structures-{mode}.log").write_bytes(result.stdout + result.stderr)
        assert result.returncode == 33 and b"INTERNAL_STRUCTURES_PASS" in result.stdout
        print(f"Public structures {mode}: PASS", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("old_map", type=Path)
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="sft-retirement-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    old = image_file(args.image, "::MSDOS.SYS")
    new = (ROOT / "src/DOS/MSDOS.SYS").read_bytes()
    _, before = parse_map(args.old_map)
    _, after = parse_map(ROOT / "src/DOS/MSDOS.MAP")
    assert before["SYSBUF"] == after["SYSBUF"]
    assert before["CARPOS"] - before["sfTabl"] == 301
    assert after["SFT001E"] - after["sfTabl"] == 301
    assert after["DOS_LOW_GATE_END"] <= after["sfTabl"] < after["SYSBUF"]
    assert old[before["sfTabl"]:before["sfTabl"] + 301] == new[after["sfTabl"]:after["SFT001E"]]
    released = rounded(before["DOS_LOW_GATE_END"]) - rounded(after["DOS_LOW_GATE_END"])
    assert released == 304
    shutil.copyfile(args.old_map, work / "old-MSDOS.MAP")
    shutil.copyfile(ROOT / "src/DOS/MSDOS.MAP", work / "MSDOS.MAP")
    (work / "MSDOS.SYS").write_bytes(new)
    provider = work / "EMM386.EXE"
    provider.write_bytes(image_file(args.image, "::DOS/EMM386.EXE"))
    build(work / "bios", early=True, tail_body=True, rebase=True, compact=True,
          high_cds=True, dispatch=True, characters=True, retire_characters=True,
          pack_headers=True, retire_media=True, pack_drive_graph=True,
          high_stack_pool=True, retire_clock=True, retire_mux=True,
          paired_provider=provider)
    candidate = work / "input.img"
    shutil.copyfile(args.image, candidate)
    install(candidate, "MSDOS.SYS", new)
    install(candidate, "IO.SYS", (work / "bios/IO.SYS").read_bytes())
    # These two utilities link private DOS layout objects. A packed prefix
    # requires a matched relink; preserving their old offsets is not valid.
    utilities = [ROOT / f"src/CMD/{name}/{name}.EXE" for name in ("SHARE", "IFSFUNC")]
    subprocess.run(["make", *(str(path) for path in utilities)], cwd=ROOT, check=True)
    kernel_fields = {name.upper(): value for name, value in after.items()}
    utility_hashes = {}
    for path in utilities:
        segments, fields = parse_map(path.with_suffix(".MAP"))
        base = segments["START"].paragraph * 16 + segments["START"].offset
        fields = {name.upper(): value - base for name, value in fields.items()}
        for name in ("SWAP_START", "CURRENTPDB", "THISSFT", "WFP_START", "CONSFT",
                     "USER_ID", "PROC_ID", "BYTPOS", "OPENBUF"):
            assert fields[name] == kernel_fields[name], (path.name, name)
        install(candidate, "DOS/" + path.name, path.read_bytes())
        utility_hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    unchanged = {}
    for name in ("CONFIG.SYS", "AUTOEXEC.BAT", "COMMAND.COM", "DOS/COMMAND.COM",
                 "DOS/HIMEM.SYS", "DOS/EMM386.EXE", "VC/VC.COM"):
        data = image_file(args.image, "::" + name)
        assert data == image_file(candidate, "::" + name), name
        unchanged[name] = hashlib.sha256(data).hexdigest()
    for source, name in (("int21_fcb_probe.asm", "I21FCB.COM"),
                         ("qemu_exit.asm", "QEXIT.COM"),
                         ("memory_ceiling_probe.asm", "CEILING.COM")):
        subprocess.run(["nasm", "-f", "bin", ROOT / "tests" / source,
                        "-o", work / name], check=True)
    assert probe(work, candidate, "high", "HIGH")
    build(work / "bios-low")
    assert probe(work, candidate, "standalone-low", "LOW",
                 bios=(work / "bios-low/IO.SYS").read_bytes())
    qualify(work, candidate)
    results = {}
    for name, image in (("before", args.image), ("after", candidate)):
        serial, screen = capture(name, image.resolve(), work, work / "CEILING.COM")
        results[name] = parse_capture(serial, screen)
        results[name]["xms"] = xms_summary(serial.read_text(encoding="latin-1"))
        print(f"{name}: {results[name]}", flush=True)
    assert results["after"]["largest"] - results["before"]["largest"] == released
    assert results["after"]["upper_free"] == results["before"]["upper_free"]
    assert results["after"]["xms"] is not None
    assert results["after"]["xms"] == results["before"]["xms"]
    results["unchanged_sha256"] = unchanged
    results["matched_utility_sha256"] = utility_hashes
    results["input_sha256"] = hashlib.sha256(candidate.read_bytes()).hexdigest()
    (work / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
