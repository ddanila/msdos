#!/usr/bin/env python3
"""Boot DOS and exercise its full cached-XMS-entry update and legacy form."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import runpy
import subprocess
import tempfile
from report_himem_residency import PROCEDURE_RE, parse_symbols

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path,
                        default=Path(os.environ.get("FLOPPY_IMAGE", ROOT / "out/floppy.img")))
    parser.add_argument("--old-kernel", type=Path,
                        help="negative control: kernel without the full-entry protocol")
    parser.add_argument("--shifted-entry", action="store_true",
                        help="development HIMEM changes its public entry offset after relocation")
    parser.add_argument("--legacy-loader", action="store_true",
                        help="negative control: retain SYSINIT's old segment-only commit")
    parser.add_argument("--legacy-kernel-fallback", action="store_true",
                        help="verify unsupported kernels boot without relocating the test provider")
    args = parser.parse_args()
    if args.legacy_loader and not args.shifted_entry:
        parser.error("legacy-loader control requires --shifted-entry")
    if args.legacy_kernel_fallback and (not args.old_kernel or not args.shifted_entry):
        parser.error("legacy fallback requires --old-kernel and --shifted-entry")
    subprocess.run(["make", "dos", "bios", str(ROOT / "src/DEV/HIMEM/HIMEM.SYS")],
                   cwd=ROOT, check=True)
    work = Path(tempfile.mkdtemp(prefix="xms-entry-handoff-", dir=ROOT / "out"))
    print(f"Evidence: {work}", flush=True)
    kernel = args.old_kernel or ROOT / "src/DOS/MSDOS.SYS"
    files = {"IO.SYS": ROOT / "src/BIOS/IO.SYS", "MSDOS.SYS": kernel,
             "HIMEM.SYS": ROOT / "src/DEV/HIMEM/HIMEM.SYS"}
    entry_offsets = {}
    if args.shifted_entry:
        files["HIMEM.SYS"] = work / "HIMEM.SYS"
        listing = work / "HIMEM.lst"
        subprocess.run([str(ROOT / "bin/jwasm-bin"), "-q", "-bin", "-DHIMEM_SHIFT_ENTRY_TEST",
                        "-Sa", f"-Fl={listing}",
                        f"-Fo{files['HIMEM.SYS']}", str(ROOT / "src/DEV/HIMEM/HIMEM.ASM")], check=True)
        for line in listing.read_text().splitlines():
            match = PROCEDURE_RE.match(line)
            if match:
                entry_offsets[match[1]] = int(match[2], 16)
        data, _ = parse_symbols(listing)
        entry_offsets["initial_segment"] = data["initial_segment"][0]
    if args.legacy_loader:
        bios = ROOT / "src/BIOS"
        obj = work / "SYSCONF.OBJ"
        subprocess.run([str(ROOT / "bin/jwasm-masm"), "-I. -I../INC -DBIOS_XMS_ENTRY_LEGACY_TEST",
                        f"SYSCONF.ASM,{obj};"], cwd=bios, check=True, stdout=subprocess.DEVNULL)
        names = ("MSBIO1", "MSCON", "MSAUX", "MSLPT", "MSCLOCK", "MSDISK", "MSBIO2",
                 "MSHARD", "MSINIT", "SYSINIT1", "SYSCONF", "SYSINIT2", "SYSIMES")
        objects = [obj if name == "SYSCONF" else bios / (name + ".OBJ") for name in names]
        linker = runpy.run_path(str(ROOT / "bin/wlink"))["wlink_bin"]()
        exe, binary = work / "MSBIO.EXE", work / "MSBIO.BIN"
        subprocess.run([str(linker), "format", "dos", "option", "quiet", "option", "nocaseexact",
                        "option", "nofarcalls", "name", str(exe),
                        *[str(arg) for path in objects for arg in ("file", path)]], check=True)
        subprocess.run([str(ROOT / "bin/exe2bin"), str(exe), str(binary)], input=b"70\n", check=True)
        files["IO.SYS"] = work / "IO.SYS"
        files["IO.SYS"].write_bytes((bios / "MSLOAD.COM").read_bytes() + binary.read_bytes())
    report = dict(passed=False, images={},
                  shifted_entry=args.shifted_entry, legacy_loader=args.legacy_loader,
                  legacy_kernel_fallback=args.legacy_kernel_fallback,
                  entry_offsets=entry_offsets,
                  emulator=subprocess.check_output(["qemu-system-i386", "--version"], text=True).splitlines()[0],
                  base_sha256=hashlib.sha256(args.image.read_bytes()).hexdigest(),
                  probe_sha256=hashlib.sha256((ROOT / "tests/xms_entry_handoff_probe.asm").read_bytes()).hexdigest(),
                  input_sha256={
        name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in files.items()})
    try:
        for mode in ("HIGH", "LOW"):
            probe = work / f"{mode}.com"
            subprocess.run(["nasm", "-f", "bin", *(["-DDOS_LOW"] if mode == "LOW" else []),
                            *(["-DLEGACY_KERNEL"] if args.legacy_kernel_fallback else []),
                            *(["-DSHIFTED_ENTRY", f"-DORIGINAL_ENTRY={entry_offsets['xms_control']}",
                               f"-DREBASED_ENTRY={entry_offsets['xms_rebased_control']}",
                               f"-DINITIAL_SEGMENT={entry_offsets['initial_segment']}"] if args.shifted_entry else []),
                            str(ROOT / "tests/xms_entry_handoff_probe.asm"), "-o", str(probe)], check=True)
            disk = work / f"{mode}.img"
            shutil.copyfile(args.image, disk)
            env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
            for name, path in dict(files, **{"HANDOFF.COM": probe}).items():
                subprocess.run(["mcopy", "-o", "-i", str(disk), str(path), "::" + name], env=env, check=True)
            for name, data in {"CONFIG.SYS": f"DEVICE=HIMEM.SYS /TESTMEM:OFF\r\nDOS={mode}\r\n",
                               "AUTOEXEC.BAT": "@ECHO OFF\r\nHANDOFF.COM\r\n"}.items():
                subprocess.run(["mcopy", "-o", "-i", str(disk), "-", "::" + name],
                               input=data.encode(), env=env, check=True)
            report["images"][mode] = hashlib.sha256(disk.read_bytes()).hexdigest()
            debug = work / f"{mode}.debug"
            result = subprocess.run([
                "qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "16",
                "-drive", f"if=floppy,format=raw,file={disk}", "-boot", "a",
                "-display", "none", "-monitor", "none", "-serial", "none", "-no-reboot",
                "-debugcon", f"file:{debug}", "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"],
                capture_output=True, timeout=25)
            (work / f"{mode}.log").write_bytes(result.stdout + result.stderr)
            if result.returncode != 33 or debug.read_bytes() != b"P":
                raise RuntimeError(f"DOS={mode} entry protocol failed: {debug.read_bytes()!r}")
            print(f"PASS: DOS={mode} cached XMS entry protocol", flush=True)
        report["passed"] = True
    finally:
        (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
