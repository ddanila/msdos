#!/usr/bin/env python3
"""DWED CPU-model smoke tests with a booted DOS; not real-BIOS acceptance."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from test_compat_bpb_qemu import disk, put, run

ROOT = Path(__file__).resolve().parents[1]
PROBES = {"TABTEST": "TAB", "STORTEST": "STORE", "SAVETEST": "SAVE", "MEMTEST": "MEM"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--boot-image", type=Path, default=ROOT / "out/floppy.img")
    parser.add_argument("--cpu", choices=("8086", "286"), action="append")
    parser.add_argument("--emulator", default="dosbox-x")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="dwed-legacy-", dir=ROOT / "out"))
    print(work, flush=True)
    report = {
        "scope": "DOSBox-X CPU models with booted parent DOS, runtime probes and launcher edit/save",
        "real_bios_acceptance": False,
        "cycles": "max",
        "boot_image_sha256": digest(args.boot_image),
        "emulator_sha256": digest(Path(shutil.which(args.emulator))),
        "build": json.loads((args.build / "build.json").read_text()),
        "cases": [],
    }
    for cpu in args.cpu or ("8086", "286"):
        directory = work / cpu
        directory.mkdir()
        boot = directory / "boot.img"
        shutil.copyfile(args.boot_image, boot)
        image, _, _ = disk(directory, {})
        spec = str(image) + "@@32256"
        for name in (
            run(["mdir", "-a", "-b", "-i", boot, "::"]).stdout.decode().splitlines()
        ):
            if name.rsplit("/", 1)[-1].upper() not in (
                "IO.SYS",
                "MSDOS.SYS",
                "COMMAND.COM",
                "SYSMENU.OVL",
            ):
                run(["mdel", "-i", boot, name])
        run(["mmd", "-i", spec, "::DWED"])
        for name in ("DWED.COM", "DWEDOVL.exe", "DWED.CFG", "dwedhelp.hlp"):
            put(spec, "DWED/" + name, (args.build / name).read_bytes())
        for name in PROBES:
            put(spec, name + ".EXE", (args.build / (name + ".exe")).read_bytes())
        run(
            [
                "nasm",
                "-f",
                "bin",
                ROOT / "tests/dwed_legacy_keys.asm",
                "-o",
                directory / "KEYDRV.COM",
            ]
        )
        put(spec, "KEYDRV.COM", (directory / "KEYDRV.COM").read_bytes())
        run(
            [
                "nasm",
                "-f",
                "bin",
                "-DEXPECT_8086=" + str(int(cpu == "8086")),
                ROOT / "tests/dwed_cpu_probe.asm",
                "-o",
                directory / "CPUCHECK.COM",
            ]
        )
        put(spec, "CPUCHECK.COM", (directory / "CPUCHECK.COM").read_bytes())
        original = b"DWED_MARKER\r\nsecond line\r\n"
        put(spec, "SAMPLE.TXT", original)
        put(spec, "HUGE.TXT", b"0123456789abcdef\r\n" * 40000)
        put(boot, "CONFIG.SYS", b"DOS=LOW\r\nFILES=40\r\nBUFFERS=15\r\n")
        commands = [
            "@ECHO OFF",
            "VER >C:\\DOSVER.TXT",
            "C:\\CPUCHECK.COM >C:\\CPU.TXT",
            "IF ERRORLEVEL 1 GOTO FAIL",
        ]
        for name in PROBES:
            commands += [
                "ECHO " + name + " >C:\\STAGE.TXT",
                "C:\\" + name + ".EXE",
                "IF ERRORLEVEL 1 GOTO FAIL",
            ]
        commands += [
            "C:",
            "CD \\DWED",
            "C:\\KEYDRV.COM",
            "ECHO LAUNCH >C:\\STAGE.TXT",
            "DWED.COM C:\\SAMPLE.TXT",
            "IF ERRORLEVEL 1 GOTO FAIL",
            "ECHO PASS >C:\\DONE.TXT",
            "GOTO END",
            ":FAIL",
            "ECHO FAIL >C:\\DONE.TXT",
            ":END",
        ]
        put(boot, "AUTOEXEC.BAT", ("\r\n".join(commands) + "\r\n").encode())
        argv = [
            args.emulator,
            "-nogui",
            "-nomenu",
            "-fastlaunch",
            "-time-limit",
            "90",
            "-set",
            "cpu core=normal",
            "-set",
            "cpu cputype=" + cpu,
            "-set",
            "cpu cycles=max",
            "-c",
            f'imgmount 2 "{image}" -t hdd -fs none',
            "-c",
            f'boot "{boot}"',
        ]
        with (directory / "emulator.log").open("w") as log:
            process = subprocess.run(
                argv,
                env={
                    **os.environ,
                    "SDL_VIDEODRIVER": "dummy",
                    "SDL_AUDIODRIVER": "dummy",
                },
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=105,
                check=False,
            )
        assert (
            run(["mtype", "-i", spec, "::CPU.TXT"]).stdout.strip() == b"CPU MODEL PASS"
        )
        logs = {}
        for name, prefix in PROBES.items():
            data = run(["mtype", "-i", boot, "::" + prefix + ".LOG"]).stdout
            logs[name] = data.decode("ascii").strip()
            assert b"PASS " in data and b"FAIL" not in data, logs
        assert run(["mtype", "-i", spec, "::DONE.TXT"]).stdout.strip() == b"PASS"
        assert run(["mtype", "-i", spec, "::SAMPLE.TXT"]).stdout == b"z" + original
        assert run(["mtype", "-i", spec, "::SAMPLE.BAK"]).stdout == original
        row = {
            "cpu": cpu,
            "passed": True,
            "probes": logs,
            "launcher_edit_save": True,
            "cpu_model_probe": True,
            "emulator_returncode": process.returncode,
        }
        report["cases"].append(row)
        (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        print(row, flush=True)


if __name__ == "__main__":
    main()
