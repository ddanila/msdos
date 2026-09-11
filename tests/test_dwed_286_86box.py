#!/usr/bin/env python3
"""Exercise staged EDIT with IBM AT BIOS in 86Box, using private floppy images."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from test_compat_bpb_qemu import put, run

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--emulator", type=Path, required=True)
    parser.add_argument("--roms", type=Path, required=True)
    parser.add_argument("--qt-platform", default="xcb")
    parser.add_argument("--timeout", type=float, default=600)
    parser.add_argument("--mode", choices=("low", "high"), action="append")
    parser.add_argument(
        "--core", type=Path, default=ROOT / "out/memory-production/files"
    )
    args = parser.parse_args()
    package = json.loads((args.package / "package.json").read_text())
    assert package["build"] == json.loads((args.build / "build.json").read_text())
    work = Path(tempfile.mkdtemp(prefix="dwed-286-", dir=ROOT / "out"))
    print(work, flush=True)
    report = {
        "status": "running",
        "package": package,
        "emulator_sha256": digest(args.emulator),
        "emulator_payload_sha256": (
            digest(args.emulator.parent / "usr/local/bin/86Box")
            if args.emulator.name == "AppRun"
            else digest(args.emulator)
        ),
        "core_sha256": {
            name: digest(args.core / name)
            for name in ("IO.SYS", "MSDOS.SYS", "COMMAND.COM", "HIMEM.SYS")
        },
        "boot_source_sha256": digest(ROOT / "src/BOOT/MSBOOT.BIN"),
        "sysmenu_sha256": digest(ROOT / "src/BIOS/SYSMENU.OVL"),
        "qt_platform": args.qt_platform,
        "rom_sha256": {
            name: digest(args.roms / name)
            for name in (
                "machines/ibmat/BIOS_5170_15NOV85_U27.BIN",
                "machines/ibmat/BIOS_5170_15NOV85_U47.BIN",
                "video/vga/ibm_vga.bin",
            )
        },
        "cases": [],
    }
    (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    try:
        for mode in args.mode or ("low", "high"):
            case = work / mode
            case.mkdir()
            image = case / "test.img"
            subprocess.run(
                [
                    "bash",
                    "-c",
                    'source "$1/tests/86box_286_lib.sh"\nmake_86box_286_boot_image "$2" "$1"',
                    "bash",
                    str(ROOT),
                    str(image),
                ],
                env={**os.environ, "MEMORY_CORE_DIR": str(args.core.resolve())},
                check=True,
                stdout=subprocess.DEVNULL,
            )
            directories = set()
            for name, expected in package["files"].items():
                data = (args.package / "files" / name).read_bytes()
                assert (
                    len(data) == expected["bytes"]
                    and hashlib.sha256(data).hexdigest() == expected["sha256"]
                )
                parent = Path(name).parent
                if str(parent) != ".":
                    directories.add(parent)
                    directories.update(p for p in parent.parents if str(p) != ".")
            for parent in sorted(directories, key=lambda p: (len(p.parts), str(p))):
                run(["mmd", "-i", image, "::" + str(parent)])
            for name in package["files"]:
                put(image, name, (args.package / "files" / name).read_bytes())
            for source, name, defines in (
                ("dwed_legacy_keys.asm", "KEYDRV.COM", []),
                ("dwed_cpu_probe.asm", "CPUCHECK.COM", ["-DEXPECT_8086=0"]),
            ):
                run(
                    [
                        "nasm",
                        "-f",
                        "bin",
                        *defines,
                        ROOT / "tests" / source,
                        "-o",
                        case / name,
                    ]
                )
                put(image, name, (case / name).read_bytes())
            # Flush DOS before signalling the host, then halt without further writes.
            # Some emulator builds hang on the Unit Tester shutdown request.
            (case / "finish.asm").write_text(
                "bits 16\norg 100h\nmov ah,0dh\nint 21h\n"
                "mov ax,00e3h\nxor dx,dx\nint 14h\n"
                "mov si,message\ncld\nnext: lodsb\ntest al,al\njz done\n"
                "mov ah,1\nxor dx,dx\nint 14h\njmp next\n"
                "done: cli\nhlt\njmp done\nmessage db 'DWED_286_FINISHED',13,10,0\n"
            )
            run(["nasm", "-f", "bin", case / "finish.asm", "-o", case / "FINISH.COM"])
            put(image, "FINISH.COM", (case / "FINISH.COM").read_bytes())
            (case / "hma.asm").write_text(
                f"bits 16\norg 100h\nmov ax,3306h\nint 21h\nand dh,10h\ncmp dh,{16 if mode == 'high' else 0}\njne fail\nmov ax,4c00h\nint 21h\nfail: mov ax,4c01h\nint 21h\n"
            )
            run(["nasm", "-f", "bin", case / "hma.asm", "-o", case / "HMACHECK.COM"])
            put(image, "HMACHECK.COM", (case / "HMACHECK.COM").read_bytes())
            put(image, "TABTEST.EXE", (args.build / "TABTEST.exe").read_bytes())
            put(image, "HIMEM.SYS", (args.core / "HIMEM.SYS").read_bytes())
            original = b"DWED_MARKER\r\nsecond line\r\n"
            put(image, "SAMPLE.TXT", original)
            config = (
                ("DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\n" if mode == "high" else "")
                + "DOS="
                + mode.upper()
                + "\r\nFILES=40\r\nBUFFERS=15\r\n"
            )
            put(image, "CONFIG.SYS", config.encode())
            batch = [
                "@ECHO OFF",
                "ECHO CPU >STAGE.TXT",
                "CPUCHECK.COM >CPU.TXT",
                "IF ERRORLEVEL 1 GOTO FAIL",
                "HMACHECK.COM",
                "IF ERRORLEVEL 1 GOTO FAIL",
                "ECHO HMA_PASS >HMA.TXT",
                "ECHO PROBE >STAGE.TXT",
                "TABTEST.EXE",
                "IF ERRORLEVEL 1 GOTO FAIL",
                "COPY A:\\TAB.LOG A:\\TABPRE.LOG >NUL",
                "ECHO KEYDRV >STAGE.TXT",
                "KEYDRV.COM",
                "ECHO EDIT >STAGE.TXT",
                "EDIT.COM A:\\SAMPLE.TXT",
                "IF ERRORLEVEL 1 GOTO FAIL",
                "ECHO COMPLETE >STAGE.TXT",
                "ECHO PASS >DONE.TXT",
                "FINISH.COM",
                ":FAIL",
                "ECHO FAIL >DONE.TXT",
                "FINISH.COM FAIL",
            ]
            put(image, "AUTOEXEC.BAT", ("\r\n".join(batch) + "\r\n").encode())
            vm = (
                (ROOT / "tests/86box/ibmat-286.cfg")
                .read_text()
                .replace("gfxcard = cga", "gfxcard = vga")
                .replace("size = 2048", "size = 512")
            )
            (case / "86box.cfg").write_text(vm)
            (case / "startup.cfg").write_text(vm)
            shutil.copyfile(ROOT / "tests/86box/global.cfg", case / "global.cfg")
            run(
                [
                    "python3",
                    ROOT / "tests/seed_86box_ibmat_nvram.py",
                    case / "nvr/ibm5170_111585.nvr",
                    "--display",
                    "vga",
                    "--extended-kib",
                    "512",
                ]
            )
            argv = [
                str(args.emulator.resolve()),
                "-N",
                "-O",
                str(case / "global.cfg"),
                "-P",
                str(case),
                "-R",
                str(args.roms.resolve()),
                "-I",
                "a:" + str(image),
                "-L",
                str(case / "86box.log"),
            ]
            initial_image_sha256 = digest(image)
            initial_nvram_sha256 = digest(case / "nvr/ibm5170_111585.nvr")
            with (case / "serial.log").open("w") as log:
                process = subprocess.Popen(
                    argv,
                    env={**os.environ, "QT_QPA_PLATFORM": args.qt_platform},
                    stdin=subprocess.DEVNULL,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                )
                try:
                    deadline = time.monotonic() + args.timeout
                    while (
                        b"DWED_286_FINISHED" not in (case / "serial.log").read_bytes()
                    ):
                        assert process.poll() is None, (case, process.returncode)
                        assert time.monotonic() < deadline, (case, "guest timeout")
                        time.sleep(0.5)
                finally:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
            assert run(["mtype", "-i", image, "::DONE.TXT"]).stdout.strip() == b"PASS"
            assert (
                run(["mtype", "-i", image, "::CPU.TXT"]).stdout.strip()
                == b"CPU MODEL PASS"
            )
            assert (
                run(["mtype", "-i", image, "::HMA.TXT"]).stdout.strip() == b"HMA_PASS"
            )
            probe = run(["mtype", "-i", image, "::TAB.LOG"]).stdout
            assert b"PASS " in probe and b"FAIL" not in probe
            assert run(["mtype", "-i", image, "::TABPRE.LOG"]).stdout == probe
            assert (
                run(["mtype", "-i", image, "::TAB.OK"]).stdout.strip()
                == b"TAB DISPLAY PASS"
            )
            assert run(["mtype", "-i", image, "::SAMPLE.TXT"]).stdout == b"z" + original
            assert run(["mtype", "-i", image, "::SAMPLE.BAK"]).stdout == original
            row = {
                "mode": mode,
                "passed": True,
                "tab_probe": probe.decode().strip(),
                "launcher_edit_save": True,
                "hma_residency_checked": True,
                "config_sha256": digest(case / "startup.cfg"),
                "initial_nvram_sha256": initial_nvram_sha256,
                "initial_image_sha256": initial_image_sha256,
                "final_image_sha256": digest(image),
            }
            report["cases"].append(row)
            (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
            print(row, flush=True)
    except Exception as error:
        report["status"] = "failed"
        report["failure"] = str(error)
        if "case" in locals():
            report["failure_case"] = str(case)
            if (case / "test.img").exists():
                stage = subprocess.run(
                    ["mtype", "-i", str(case / "test.img"), "::STAGE.TXT"],
                    capture_output=True,
                    check=False,
                )
                report["failure_stage"] = stage.stdout.decode(
                    "ascii", errors="replace"
                ).strip()
        raise
    else:
        report["status"] = "passed"
    finally:
        (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
