#!/usr/bin/env python3
"""Qualify Baltic CONFIG, DOS country APIs and NLSFUNC transitions in guests."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from country_records import read_records
from ru_profiles import CONFIG, require_profile, verify_base
from test_ru_country_qemu import command

ROOT = Path(__file__).resolve().parents[1]
COUNTRY = ROOT / "src/DEV/COUNTRY/COUNTRY.SYS"
LANGUAGES = {"et": 372, "lv": 371, "lt": 370}


def compile_probes(work):
    reference = json.loads((ROOT / "locales/baltic/review/country-expectations.json").read_text())["countries"]
    old = json.loads((ROOT / "locales/ru/dos622-reference.json").read_text())["country_records"]
    filelist = bytes.fromhex(old["437"]["objects"]["5"]["payload"])
    for language, number in LANGUAGES.items():
        for page in (775, 437, 850):
            directory = work / f"{language}-{page}"
            directory.mkdir()
            data = reference[language][str(page)]
            for name, field in (("info", "country_info_hex"), ("upper", "uppercase_hex"),
                                ("collate", "collation_hex"), ("all-upper", "uppercase_hex")):
                payload = bytes.fromhex(data[field])
                (directory / (name + ".bin")).write_bytes(payload[128:] if name == "upper" else payload)
            (directory / "filelist.bin").write_bytes(filelist)
            for prefix, flags in (("P", []), ("Q", ["-DQUERY_ONLY"]), ("S", ["-DSET_COUNTRY"])):
                command("nasm", "-f", "bin", f"-DPAGE={page}", f"-DCOUNTRY={number}", *flags,
                        str(ROOT / "tests/ru_country_probe.asm"), "-o", str(work / f"{prefix}{number}{page}.COM"), cwd=directory)
        command("nasm", "-f", "bin", f"-DCOUNTRY={number}", "-DSET_REJECTION", str(ROOT / "tests/ru_country_reject.asm"),
                "-o", str(work / f"R{number}.COM"))
    for source, name in (("qemu_exit.asm", "QEXIT.COM"), ("ru_codepage_probe.asm", "CPCHK.COM")):
        command("nasm", "-f", "bin", str(ROOT / "tests" / source), "-o", str(work / name))
    for profile in CONFIG:
        command("nasm", "-f", "bin", f"-DHIGH={int(profile == 'high')}", str(ROOT / "tests/ru_profile_probe.asm"),
                "-o", str(work / (profile.upper() + ".COM")))


def run_case(work, base, profile, name, number, page, actions, corruption=None):
    folder = work / profile / name
    folder.mkdir(parents=True)
    image = folder / "boot.img"
    shutil.copyfile(base, image)
    def copy(source, target):
        command("mcopy", "-o", "-i", str(image), str(source), f"::{target}")
    for probe in work.glob("*.COM"):
        copy(probe, probe.name)
    country = COUNTRY
    if corruption:
        kind, index = {"case": (2, 0xe4 - 128), "collation": (6, 0xe4)}[corruption]
        data = bytearray(COUNTRY.read_bytes())
        obj = read_records(data)[number, 775][kind]
        data[obj["offset"] + 10 + index] ^= 1
        country = folder / "COUNTRY.SYS"
        country.write_bytes(data)
    copy(country, "COUNTRY.SYS")
    for source, target in (("DEV/DISPLAY/EGA/EGA775.CPI", "EGA775.CPI"),
                           ("DEV/DISPLAY/EGA/EGA.CPI", "EGA.CPI"),
                           ("DEV/DISPLAY/DISPLAY.SYS", "DISPLAY.SYS"),
                           ("CMD/MODE/MODE.COM", "MODE.COM"),
                           ("CMD/NLSFUNC/NLSFUNC.EXE", "NLSFUNC.EXE")):
        copy(ROOT / "src" / source, target)
    config = f"COUNTRY={number},{page},COUNTRY.SYS\r\n" + CONFIG[profile]
    config += "DEVICE=DISPLAY.SYS CON=(EGA,437,(3,3))\r\n"
    batch = ["@ECHO OFF", "CTTY AUX", profile.upper() + ".COM", "IF ERRORLEVEL 1 GOTO FAIL"]
    for action in actions:
        batch += [action, "IF ERRORLEVEL 1 GOTO FAIL"]
    batch += ["ECHO BALTIC_COUNTRY_DONE", "QEXIT.COM", ":FAIL", "ECHO BALTIC_CASE_FAIL", "QEXIT.COM"]
    for filename, contents in (("CONFIG.SYS", config), ("AUTOEXEC.BAT", "\r\n".join(batch) + "\r\n")):
        path = folder / filename
        path.write_bytes(contents.encode("ascii"))
        copy(path, filename)
    log = folder / "serial.log"
    args = [os.environ.get("QEMU", "qemu-system-i386"), "-display", "none", "-m", "8",
            "-drive", f"if=floppy,index=0,format=raw,file={image},cache=writethrough", "-boot", "a",
            "-serial", "stdio", "-monitor", "none", "-no-reboot",
            "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"]
    with log.open("wb") as output:
        result = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT, timeout=45)
    output = log.read_bytes()
    assert result.returncode == 33, (log, result.returncode, output)
    require_profile(output, profile)
    if corruption:
        stage = b"03" if corruption == "case" else b"08"
        assert b"RU_COUNTRY_FAIL stage " + stage in output and b"BALTIC_COUNTRY_DONE" not in output, (log, output)
    else:
        assert b"FAIL" not in output and b"BALTIC_COUNTRY_DONE" in output, (log, output)
        counts = {b"RU_COUNTRY_PASS": sum(a.startswith(("P3", "S3")) for a in actions),
                  b"RU_QUERY_PASS": sum(a.startswith("Q3") for a in actions),
                  b"RU_REJECTION_PASS": sum(a.startswith("R3") for a in actions),
                  b"RU_CODEPAGE_PASS": actions.count("CPCHK.COM")}
        for marker, count in counts.items():
            assert output.count(marker) == count, (log, marker, count, output)
    print(f"PASS: {profile}/{name}", flush=True)
    return {"profile": profile, "name": name, "emulator_exit": result.returncode,
            "config": config, "actions": actions, "corruption": corruption,
            "serial_log": str(log.relative_to(work)), "serial_sha256": hashlib.sha256(output).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=tuple(CONFIG), action="append")
    parser.add_argument("--case", help="run one named case")
    args = parser.parse_args()
    base = Path(os.environ.get("FLOPPY_IMAGE", ROOT / "out/floppy.img"))
    core = verify_base(base)
    work = Path(tempfile.mkdtemp(prefix="baltic-country-", dir=ROOT / "out"))
    print(f"Baltic country artifacts: {work}", flush=True)
    compile_probes(work)
    cases = []
    for language, number in LANGUAGES.items():
        for page in (775, 437, 850, ""):
            cases.append((f"config-{language}-{page or 'default'}", number, page,
                          [f"P{number}{page or 775}.COM"], None))
    actions = ["P372775.COM", "NLSFUNC", "MODE CON CP PREPARE=((775) EGA775.CPI)",
               "MODE CON CP PREPARE=((,437,850) EGA.CPI)"]
    for number in (372, 371, 370, 372):
        other = 371 if number == 372 else 372
        actions += [f"S{number}775.COM", f"Q{other}775.COM", f"P{number}775.COM"]
        for page in (775, 437, 850, 775):
            actions += [f"CHCP {page}", "CPCHK.COM", f"P{number}{page}.COM",
                        f"Q{number}{850 if page == 775 else 775}.COM"]
        actions += [f"R{number}.COM", "CPCHK.COM", f"P{number}775.COM"]
    cases += [("transitions", 372, 775, actions, None),
              ("wrong-case", 372, 775, ["P372775.COM"], "case"),
              ("wrong-collation", 372, 775, ["P372775.COM"], "collation")]
    if args.case and args.case not in {case[0] for case in cases}:
        raise SystemExit("unknown country case")
    report = {"schema_version": 1, "status": "running", "core_sha256": core,
              "country_sha256": hashlib.sha256(COUNTRY.read_bytes()).hexdigest(),
              "base_image_sha256": hashlib.sha256(base.read_bytes()).hexdigest(), "cases": []}
    for profile in args.profile or list(CONFIG):
        for name, number, page, actions, corruption in cases:
            if args.case and name != args.case:
                continue
            report["cases"].append(run_case(work, base, profile, name, number, page, actions, corruption))
            (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    report["status"] = "selected-cases-passed" if args.case or args.profile else "passed"
    (work / "results.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
