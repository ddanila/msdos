#!/usr/bin/env python3
"""Exercise CONFIG country loading, NLS APIs and CHCP transitions in private guests."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from country_records import read_records
from ru_profiles import require_profile

ROOT = Path(__file__).resolve().parents[1]
COUNTRY = ROOT / "src/DEV/COUNTRY/COUNTRY.SYS"


def command(*args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def compile_probes(work):
    reference = json.loads((ROOT / "locales/ru/dos622-reference.json").read_text())["country_records"]
    for page in (866, 437, 850):
        directory = work / str(page)
        directory.mkdir()
        objects = reference[str(page)]["objects"]
        for name, kind in [("info", "1"), ("upper", "2"), ("collate", "6"), ("filelist", "5")]:
            obj = objects.get(kind, reference["437"]["objects"][kind])
            (directory / f"{name}.bin").write_bytes(bytes.fromhex(obj["payload"]))
        # ASCII rules are independent of the NLS high-byte table.
        low = bytes(i - 32 if 97 <= i <= 122 else i for i in range(128))
        (directory / "all-upper.bin").write_bytes(low + (directory / "upper.bin").read_bytes())
        command("nasm", "-f", "bin", f"-DPAGE={page}", str(ROOT / "tests/ru_country_probe.asm"),
                "-o", str(work / f"P{page}.COM"), cwd=directory)
        command("nasm", "-f", "bin", f"-DPAGE={page}", "-DQUERY_ONLY", str(ROOT / "tests/ru_country_probe.asm"),
                "-o", str(work / f"Q{page}.COM"), cwd=directory)
    for source, name in [("qemu_exit.asm", "QEXIT.COM"), ("ru_country_reject.asm", "REJECT.COM"),
                         ("ru_codepage_probe.asm", "CPCHK.COM")]:
        command("nasm", "-f", "bin", str(ROOT / "tests" / source), "-o", str(work / name))


def run_case(work, base, name, config, actions, expected_count, corrupt=False, profile=None):
    directory = work / name
    directory.mkdir()
    image = directory / "boot.img"
    shutil.copyfile(base, image)
    def copy(source, name):
        command("mcopy", "-o", "-i", str(image), str(source), f"::{name}")
    for name in ("P866.COM", "P437.COM", "P850.COM", "Q866.COM", "Q437.COM", "Q850.COM", "QEXIT.COM", "REJECT.COM", "CPCHK.COM"):
        copy(work / name, name)
    if profile:
        copy(work / "PROFILE.COM", "PROFILE.COM")
        actions = ["PROFILE.COM"] + actions
    country = COUNTRY
    if corrupt:
        data = bytearray(COUNTRY.read_bytes())
        offset = read_records(data)[7, 866][2]["offset"] + 10 + 0xf1 - 128
        data[offset] = 0xf1
        country = directory / "COUNTRY.SYS"
        country.write_bytes(data)
    copy(country, "COUNTRY.SYS")
    for source, name in [("DEV/DISPLAY/EGA/EGA866.CPI", "EGA866.CPI"),
                         ("DEV/DISPLAY/EGA/EGA.CPI", "EGA.CPI"),
                         ("DEV/DISPLAY/DISPLAY.SYS", "DISPLAY.SYS"),
                         ("CMD/MODE/MODE.COM", "MODE.COM"),
                         ("CMD/NLSFUNC/NLSFUNC.EXE", "NLSFUNC.EXE")]:
        copy(ROOT / "src" / source, name)
    batch = ["@ECHO OFF", "CTTY AUX"]
    for action in actions:
        batch.extend([action, "IF ERRORLEVEL 1 GOTO FAIL"])
    batch.extend(["ECHO RU_COUNTRY_DONE", "QEXIT.COM", ":FAIL", "ECHO RU_CASE_FAIL", "QEXIT.COM"])
    for name, data in [("CONFIG.SYS", config), ("AUTOEXEC.BAT", "\r\n".join(batch) + "\r\n")]:
        command("mcopy", "-o", "-i", str(image), "-", f"::{name}", input=data.encode())
    log = directory / "serial.log"
    args = [os.environ.get("QEMU", "qemu-system-i386"), "-display", "none", "-m", "8" if profile else "4",
            "-drive", f"if=floppy,index=0,format=raw,file={image},cache=writethrough", "-boot", "a",
            "-serial", "stdio", "-monitor", "none", "-no-reboot",
            "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
    with log.open("wb") as output:
        result = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT, timeout=30)
    output = log.read_bytes()
    if result.returncode != 33:
        raise AssertionError(f"emulator exit {result.returncode}: {log}\n{output!r}")
    if profile:
        require_profile(output,profile)
    if corrupt:
        if b"RU_COUNTRY_FAIL stage 03" not in output or b"RU_COUNTRY_DONE" in output:
            raise AssertionError(f"wrong-case control escaped the oracle: {log}\n{output!r}")
    elif b"FAIL" in output or b"RU_COUNTRY_DONE" not in output or output.count(b"RU_COUNTRY_PASS") != expected_count:
        raise AssertionError(f"country contract failed: {log}\n{output!r}")
    if not corrupt:
        for action, marker in [("REJECT.COM", b"RU_REJECTION_PASS"), ("CPCHK.COM", b"RU_CODEPAGE_PASS")]:
            if output.count(marker) != actions.count(action):
                raise AssertionError(f"missing {action} completion: {log}")
        if output.count(b"RU_QUERY_PASS") != sum(action in ("Q437.COM", "Q850.COM", "Q866.COM") for action in actions):
            raise AssertionError(f"missing external-query completion: {log}")
    print(f"PASS: {directory.name}", flush=True)
    return {"profile": profile, "name": directory.name, "emulator_exit": result.returncode,
            "country_probe_passes": output.count(b"RU_COUNTRY_PASS"), "negative_control": corrupt,
            "config": config, "actions": actions, "serial_log": str(log.relative_to(work)),
            "serial_sha256": hashlib.sha256(output).hexdigest()}


def main():
    base = Path(os.environ.get("FLOPPY_IMAGE", ROOT / "out/floppy.img"))
    work = Path(tempfile.mkdtemp(prefix="ru-country-", dir=ROOT / "out"))
    print(f"Russian country artifacts: {work}", flush=True)
    compile_probes(work)
    results = []
    for page in (866, 437, 850):
        results.append(run_case(work, base, f"config-{page}", f"COUNTRY=007,{page},COUNTRY.SYS\r\n",
                                [f"P{page}.COM"], 1))
    results.append(run_case(work, base, "config-default", "COUNTRY=007,,COUNTRY.SYS\r\n", ["P866.COM"], 1))
    actions = ["P866.COM", "NLSFUNC", "MODE CON CP PREPARE=((866) EGA866.CPI)",
               "MODE CON CP PREPARE=((,437,850) EGA.CPI)"]
    for page in (866, 437, 850, 866):
        actions.extend([f"CHCP {page}", "CPCHK.COM", f"P{page}.COM",
                        "Q850.COM" if page == 866 else "Q866.COM"])
    actions.extend(["REJECT.COM", "CPCHK.COM", "P866.COM"])
    results.append(run_case(work, base, "transitions", "COUNTRY=007,866,COUNTRY.SYS\r\n"
                            "DEVICE=DISPLAY.SYS CON=(EGA,437,(3,3))\r\n", actions, 6))
    results.append(run_case(work, base, "wrong-case", "COUNTRY=007,866,COUNTRY.SYS\r\n", ["P866.COM"], 0, corrupt=True))
    (work / "results.json").write_text(json.dumps({"schema_version": 1,
        "country_sys_sha256": hashlib.sha256(COUNTRY.read_bytes()).hexdigest(),
        "base_image_sha256": hashlib.sha256(base.read_bytes()).hexdigest(), "cases": results}, indent=2) + "\n")


if __name__ == "__main__":
    main()
