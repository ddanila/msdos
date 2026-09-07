#!/usr/bin/env python3
"""Compare complete dispatcher-table retirement in the current BIOS/shell image."""
import argparse
import hashlib
import json
from pathlib import Path
import re
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
    assert b.get("DOS_INSTALL_TABLE_END", b["INTERCHAR"]) - b["FOO"] == a["DOS_INSTALL_TABLE_END"] - a["FOO"] == 115
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


def qualify_ifs(work, candidate, low_bios):
    """Exercise internal-service consumers without replacing the boot drive."""
    for source, name in (("config_ifs_driver.asm", "TESTIFS.SYS"),
                         ("ifsfunc_filesys_probe.asm", "IFSPROBE.COM"),
                         ("qemu_exit.asm", "QEXIT.COM")):
        subprocess.run(["nasm", "-f", "bin", ROOT / "tests" / source,
                        "-o", work / name], check=True)
    commands = ["@ECHO OFF", "CTTY AUX", "PATH C:\\DOS"]
    expected = []
    for command, label, rejected in (
        ("IFSFUNC NAMES=256", "RANGE", True),
        ("IFSFUNC NAMES=1 NAMES=2", "REPEAT", True),
        ("IFSFUNC NAMES=7", "INSTALL", False),
        ("FILESYS D: TESTIFS", "ATTACH", False),
        ("FILESYS D: TESTIFS", "DUPLICATE", True),
        ("FILESYS E: NOIFS", "UNKNOWN", True),
        ("FILESYS D:", "STATUS", False),
        ("FILESYS D: /D", "DETACH", False),
        ("FILESYS D: /D", "REPEAT_DETACH", True),
        ("FILESYS D:", "EMPTY", False),
        ("IFSPROBE.COM", "COUNTERS", False),
    ):
        good, bad = ("", "NOT ") if rejected else ("NOT ", "")
        commands.extend((command, f"IF {bad}ERRORLEVEL 1 ECHO IFS_{label}_FAILED",
                         f"IF {good}ERRORLEVEL 1 ECHO IFS_{label}_PASS"))
        expected.append(f"IFS_{label}_PASS".encode())
    commands.extend(("ECHO IFS_DONE", "QEXIT.COM"))
    for mode in ("HIGH", "LOW"):
        disk = work / f"ifs-{mode}.img"
        shutil.copyfile(candidate, disk)
        config = image_file(candidate, "::CONFIG.SYS")
        if mode == "LOW":
            install(disk, "IO.SYS", low_bios.read_bytes())
            config = b"DOS=LOW\r\nFILES=30\r\nBUFFERS=15\r\nLASTDRIVE=Z\r\n"
        install(disk, "CONFIG.SYS", config.rstrip() + b"\r\nIFS=C:\\TESTIFS.SYS\r\n")
        for name in ("TESTIFS.SYS", "IFSPROBE.COM", "QEXIT.COM"):
            install(disk, name, (work / name).read_bytes())
        install(disk, "AUTOEXEC.BAT", ("\r\n".join(commands) + "\r\n").encode())
        result = subprocess.run([
            "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
            "-display", "none", "-monitor", "none", "-serial", "stdio", "-boot", "c",
            "-no-reboot", "-drive", f"if=ide,format=raw,file={disk}",
            "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
            capture_output=True, timeout=40)
        output = result.stdout + result.stderr
        (work / f"ifs-{mode}.log").write_bytes(output)
        assert result.returncode == 33 and b"IFS_DONE" in output, output
        assert b"_FAILED" not in output and all(marker in output for marker in expected), output
        assert re.search(rb"D:\s+TESTIFS(?:\s|$)", output), output
        assert b"No entries found" in output, output
        print(f"IFSFUNC/FILESYS {mode}: PASS", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("old_map", type=Path)
    parser.add_argument("--console-workspace", action="store_true",
                        help="compare complete private-console workspace retirement after dispatch retirement")
    args = parser.parse_args()
    prefix = "dos-console-retirement-" if args.console_workspace else "dos-dispatch-retirement-"
    work = Path(tempfile.mkdtemp(prefix=prefix, dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    old = image_file(args.image, "::MSDOS.SYS")
    new = (ROOT / "src/DOS/MSDOS.SYS").read_bytes()
    _, before = parse_map(args.old_map)
    _, after = parse_map(ROOT / "src/DOS/MSDOS.MAP")
    high_growth = after["SYSBUF"] - before["SYSBUF"]
    assert high_growth == (16 if args.console_workspace else 0)
    assert after["DOSINIT"] - before["DOSINIT"] == high_growth
    assert after["DOS_LOW_GATE_END"] < after["MAXCALL"] < after["DOS_INSTALL_TABLE_END"] < after["SYSBUF"]
    released = rounded(before["DOS_LOW_GATE_END"]) - rounded(after["DOS_LOW_GATE_END"])
    assert released == (256 if args.console_workspace else 336)
    if args.console_workspace:
        assert before["PFLAG"] - before["INBUF"] == 259
        assert after["CONSOLE_WORKSPACE_END"] - after["INBUF"] == 259
        assert after["CONBUF"] - after["INBUF"] == 128
        assert after["INBUF"] >= after["DOS_LOW_GATE_END"]
        assert old[before["INBUF"]:before["PFLAG"]] == new[after["INBUF"]:after["CONSOLE_WORKSPACE_END"]]
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
    qualify_ifs(work, candidate, work / "bios-low/IO.SYS")
    results = dict(dispatch_targets=targets, high_image_growth=high_growth,
                   unchanged_sha256=unchanged,
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
    print(f"Composed owner retirement: +{released} conventional bytes", flush=True)


if __name__ == "__main__":
    main()
