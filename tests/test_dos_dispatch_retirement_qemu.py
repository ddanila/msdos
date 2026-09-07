#!/usr/bin/env python3
"""Compare complete dispatcher-table retirement in the current BIOS/shell image."""
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
from test_sft_retirement_qemu import qualify
from test_umb_subpage_composition import xms_summary


def check_tables(old, new, before, after):
    """All function words must still name the same linked routines, not old offsets."""
    b = {name.upper(): value for name, value in before.items()}
    a = {name.upper(): value for name, value in after.items()}
    assert b["FOO"] - b["MAXCALL"] == a["DOS_DISPATCH_TABLE_END"] - a["MAXCALL"] == 220
    assert b["INTERCHAR"] - b["FOO"] == a["DOS_INSTALL_TABLE_END"] - a["FOO"] == 115
    assert old[b["MAXCALL"]:b["MAXCALL"]+2] == new[a["MAXCALL"]:a["MAXCALL"]+2]
    assert old[b["FOO"]+4] == new[a["FOO"]+4] == 55
    assert int.from_bytes(old[b["DTAB"]:b["DTAB"]+2], "little") == b["FOO"]+4
    assert int.from_bytes(new[a["DTAB"]:a["DTAB"]+2], "little") == a["FOO"]+4
    pairs = [(b["DISPATCH"]+i*2, a["DISPATCH"]+i*2) for i in range(109)]
    pairs += [(b["FOO"], a["FOO"])]
    pairs += [(b["FOO"]+5+i*2, a["FOO"]+5+i*2) for i in range(55)]
    targets = []
    for old_at, new_at in pairs:
        old_target = int.from_bytes(old[old_at:old_at+2], "little")
        new_target = int.from_bytes(new[new_at:new_at+2], "little")
        names = [name for name, offset in b.items() if offset == old_target and a.get(name) == new_target]
        assert names, (old_at, new_at, old_target, new_target)
        targets.append(dict(old_offset=old_at, new_offset=new_at, target_names=names))
    return targets


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("old_map", type=Path)
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="dos-dispatch-retirement-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    old = image_file(args.image, "::MSDOS.SYS")
    new = (ROOT / "src/DOS/MSDOS.SYS").read_bytes()
    _, before = parse_map(args.old_map)
    _, after = parse_map(ROOT / "src/DOS/MSDOS.MAP")
    assert before["SYSBUF"] == after["SYSBUF"]
    assert before["DOSINIT"] == after["DOSINIT"]
    assert after["DOS_LOW_GATE_END"] < after["MAXCALL"] < after["DOS_INSTALL_TABLE_END"] < after["SYSBUF"]
    released = rounded(before["DOS_LOW_GATE_END"]) - rounded(after["DOS_LOW_GATE_END"])
    assert released == 336
    targets = check_tables(old, new, before, after)
    shutil.copyfile(args.old_map, work / "old-MSDOS.MAP")
    shutil.copyfile(ROOT / "src/DOS/MSDOS.MAP", work / "MSDOS.MAP")
    (work / "MSDOS.SYS").write_bytes(new)
    provider = work / "EMM386.EXE"
    provider.write_bytes(image_file(args.image, "::DOS/EMM386.EXE"))
    build(work / "bios", early=True, tail_body=True, rebase=True, compact=True,
          high_cds=True, dispatch=True, characters=True, retire_characters=True,
          pack_headers=True, retire_media=True, pack_drive_graph=True,
          high_stack_pool=True, retire_clock=True, retire_mux=True,
          compact_tracks=True, retire_swap=True, retire_ioctl_state=True,
          paired_provider=provider)
    candidate = work / "input.img"
    shutil.copyfile(args.image, candidate)
    install(candidate, "MSDOS.SYS", new)
    install(candidate, "IO.SYS", (work / "bios/IO.SYS").read_bytes())
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
    assert probe(work, candidate, "standalone-low", "LOW", bios=(work / "bios-low/IO.SYS").read_bytes())
    qualify(work, candidate)
    results = dict(dispatch_targets=targets, unchanged_sha256=unchanged,
                   matched_utilities_sha256=utility_hashes,
                   old_kernel_sha256=hashlib.sha256(old).hexdigest(),
                   kernel_sha256=hashlib.sha256(new).hexdigest())
    for name, disk in (("after", candidate), ("before", args.image)):
        serial, screen = capture(name, disk.resolve(), work, work / "CEILING.COM")
        results[name] = parse_capture(serial, screen)
        results[name]["xms"] = xms_summary(serial.read_text(encoding="latin-1"))
        (work / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    assert results["after"]["largest"] - results["before"]["largest"] == released
    assert results["after"]["upper_free"] == results["before"]["upper_free"]
    assert results["after"]["xms"] is not None
    assert results["after"]["xms"] == results["before"]["xms"]
    print(f"Composed dispatcher retirement: +{released} conventional bytes", flush=True)


if __name__ == "__main__":
    main()
