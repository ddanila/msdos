#!/usr/bin/env python3
"""Download pinned archive.org DOS applications and capture paired QEMU startups.

External software stays in .reference; images and evidence stay in out.
Use --prepare-only to download/install, then --program/--profile to narrow runs.
"""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import difflib
from datetime import datetime, timezone
import hashlib
import io
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile

from capture_vc_memory_comparison import partition_offset, image_file
from screen_expect import QMPConnection, read_screen_text, send_keys

ROOT = Path(__file__).resolve().parents[1]
ENV = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")
PROFILES = {
    "low": "DOS=LOW\r\nFILES=30\r\nBUFFERS=15\r\nLASTDRIVE=Z\r\nFCBS=4,0\r\n",
    "xms": "DEVICE=C:\\DOS\\HIMEM.SYS /TESTMEM:OFF\r\nDOS=HIGH\r\nFILES=30\r\nBUFFERS=15\r\nLASTDRIVE=Z\r\nFCBS=4,0\r\n",
    "high": "DEVICE=C:\\DOS\\HIMEM.SYS /TESTMEM:OFF\r\nDEVICE=C:\\DOS\\EMM386.EXE 2048 RAM\r\nDOS=HIGH,UMB\r\nFILES=30\r\nBUFFERS=15\r\nLASTDRIVE=Z\r\nFCBS=4,0\r\n",
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(command, **kw):
    return subprocess.run([str(s) for s in command], env=ENV, check=True, **kw)


def install(image, name, data, floppy=False):
    spec = str(image) if floppy else f"{image}@@{partition_offset(image)}"
    run(["mcopy", "-o", "-i", spec, "-", "::" + name], input=data)


def unzip(z, directory):
    # Refuse paths that escape the destination, including nested packages.
    for member in z.infolist():
        target = (directory / member.filename).resolve()
        if not target.is_relative_to(directory.resolve()):
            raise ValueError(f"unsafe archive member: {member.filename}")
        if member.create_system == 3 and (member.external_attr >> 16) & 0o170000 == 0o120000:
            raise ValueError(f"archive symlink: {member.filename}")
    if any(m.compress_type not in (0, 8, 12, 14) for m in z.infolist()):
        # Historical ZIP shrinking/imploding is supported by Info-ZIP, but
        # not Python's zipfile. Keep the same path checks for both extractors.
        with tempfile.TemporaryDirectory(prefix="dosapp-zip-") as temporary:
            archive = Path(temporary) / "legacy.zip"
            z.fp.seek(0)
            archive.write_bytes(z.fp.read())
            run(["unzip", "-oq", archive, "-d", directory])
        return
    z.extractall(directory)


def package_files(package, cache):
    archive = cache / package.get("cache_name", package["file"])
    url = "https://archive.org/download/" + package["item"] + "/" + urllib.parse.quote(package["file"])
    if not archive.exists():
        partial = archive.with_suffix(archive.suffix + ".partial")
        with urllib.request.urlopen(url, timeout=60) as source, partial.open("wb") as out:
            shutil.copyfileobj(source, out)
        partial.replace(archive)
    digest = sha(archive)
    if package.get("sha256") and digest != package["sha256"]:
        raise ValueError(f"checksum mismatch: {archive}")
    directory = cache / (package["id"] + "-extracted")
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir()
    if package["format"] == "file":
        shutil.copyfile(archive, directory / Path(package["file"]).name)
    elif package["format"] == "floppy":
        run(["mcopy", "-s", "-i", archive, "::*", directory])
    elif package["format"] == "zip-floppy":
        with zipfile.ZipFile(archive) as z, tempfile.TemporaryDirectory(prefix="dosapp-img-") as temporary:
            disk = Path(temporary) / "disk.img"
            disk.write_bytes(z.read(package["image_member"]))
            run(["mcopy", "-s", "-i", disk, "::*", directory])
    else:
        with zipfile.ZipFile(archive) as z:
            if package["format"] == "nested-zip":
                for name in z.namelist():
                    with zipfile.ZipFile(io.BytesIO(z.read(name))) as nested:
                        unzip(nested, directory)
            else:
                unzip(z, directory)
    for name in package.get("exclude", []):
        p = directory / name
        if p.is_dir():
            shutil.rmtree(p)
        elif p.exists():
            p.unlink()
    return directory / package.get("subdir", ""), {"url": url, "sha256": digest}


def build_fork(retail, floppy, output):
    disk = output / "fork-system.img"
    boot = output / "transfer.img"
    shutil.copyfile(retail, disk)
    shutil.copyfile(floppy, boot)
    exit_com = output / "QEXIT.COM"
    run(["nasm", "-f", "bin", ROOT / "tests/qemu_exit.asm", "-o", exit_com])
    install(boot, "QEXIT.COM", exit_com.read_bytes(), True)
    install(boot, "CONFIG.SYS", b"FILES=30\r\n", True)
    install(boot, "AUTOEXEC.BAT", b"@ECHO OFF\r\nCTTY AUX\r\nSYS C:\r\nIF ERRORLEVEL 1 ECHO TRANSFER_FAILED\r\nECHO TRANSFER_DONE\r\nQEXIT.COM\r\n", True)
    result = subprocess.run(["qemu-system-i386", "-display", "none", "-monitor", "none",
        "-machine", "pc", "-cpu", "486", "-m", "8", "-boot", "a", "-serial", "stdio", "-no-reboot",
        "-drive", f"if=floppy,format=raw,file={boot}", "-drive", f"if=ide,format=raw,file={disk}",
        "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04"], capture_output=True, timeout=45)
    (output / "transfer.log").write_bytes(result.stdout + result.stderr)
    if b"System transferred" not in result.stdout or b"TRANSFER_FAILED" in result.stdout or b"TRANSFER_DONE" not in result.stdout:
        raise RuntimeError("SYS transfer failed; inspect transfer.log")
    # SYS preserves an existing shell; explicitly install the matching COMMAND.
    install(disk, "COMMAND.COM", subprocess.check_output(
        ["mtype", "-i", str(floppy), "::COMMAND.COM"], env=ENV))
    for name in ("IO.SYS", "MSDOS.SYS", "COMMAND.COM"):
        expected = subprocess.check_output(["mtype", "-i", str(floppy), "::" + name], env=ENV)
        assert image_file(disk, "::" + name) == expected, name
    for name in ("HIMEM.SYS", "EMM386.EXE", "COMMAND.COM"):
        data = subprocess.check_output(["mtype", "-i", str(floppy), "::" + name], env=ENV)
        install(disk, "DOS/" + name, data)
    return disk


def capture(base, program, profile, label, output, seconds):
    directory = output / (program["id"] + "-" + profile + "-" + label)
    directory.mkdir()
    disk = directory / "boot.img"
    shutil.copyfile(base, disk)
    install(disk, "CONFIG.SYS", PROFILES[profile].encode())
    autoexec = ("@ECHO OFF\r\nPATH C:\\DOS\r\nPROMPT $P$G\r\n"
                f"CD \\APPS\\{program['package'].upper()}\r\nCLS\r\n"
                f"ECHO APP_START_{program['id']}\r\n{program['command']}\r\n"
                f"ECHO APP_RETURN_{program['id']}\r\n")
    install(disk, "AUTOEXEC.BAT", autoexec.encode())
    (directory / "CONFIG.SYS").write_bytes(PROFILES[profile].encode())
    (directory / "AUTOEXEC.BAT").write_bytes(autoexec.encode())
    # Keep Unix sockets short even when output paths are deep.
    with tempfile.TemporaryDirectory(prefix="dosapp-") as sockets:
        sock = Path(sockets) / "qmp"
        # See test_qemu_near_call_wrap.py: direct TB chaining can bypass IP masking.
        command = ["qemu-system-i386", "-machine", "pc", "-cpu", "486", "-m", "8",
            "-d", "nochain",
            "-rtc", "base=1995-01-02T12:00:00,clock=vm", "-display", "none", "-monitor", "none",
            "-serial", f"file:{directory}/serial.log", "-no-reboot", "-nic", "none", "-boot", "c",
            "-drive", f"if=ide,format=raw,file={disk}", "-qmp", f"unix:{sock},server=on,wait=off"]
        (directory / "command.json").write_text(json.dumps(command, indent=2) + "\n")
        with (directory / "qemu.log").open("wb") as log:
            process = subprocess.Popen(command, stdout=log, stderr=log)
            qmp = None
            screens = []
            try:
                qmp = QMPConnection(str(sock), retries=30)
                deadline = time.monotonic() + seconds
                ready_at = None
                action_index = 0
                while time.monotonic() < deadline:
                    screen = read_screen_text(qmp, str(directory / "vram.bin"))
                    if not screens or screen != screens[-1]:
                        screens.append(screen)
                    actions = program.get("actions", [])
                    if action_index < len(actions) and actions[action_index]["after"] in screen:
                        send_keys(qmp, actions[action_index]["keys"])
                        action_index += 1
                    if all(token in screen for token in program["expect"]):
                        if ready_at is None:
                            ready_at = time.monotonic()
                        if time.monotonic() - ready_at >= 1:
                            break
                    else:
                        ready_at = None
                    time.sleep(.3)
                qmp.human_cmd("stop")
                (directory / "registers.txt").write_text(qmp.human_cmd("info registers"))
                screen = read_screen_text(qmp, str(directory / "vram.bin"))
                qmp.human_cmd(f'screendump "{directory}/screen.ppm"')
                (directory / "screen.txt").write_text(screen)
                (directory / "screens.json").write_text(json.dumps(screens, indent=2) + "\n")
            finally:
                if qmp:
                    qmp.close()
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    ready = all(token in screen for token in program["expect"])
    # Verify displayed DOS free-space values independently against the FAT.
    disk_free = subprocess.check_output(["mdir", "-i", f"{disk}@@{partition_offset(disk)}", "::"], env=ENV).decode()
    free_match = re.search(r"([0-9 ][0-9 ]*) bytes free", disk_free)
    free_bytes = int(free_match.group(1).replace(" ", "")) if free_match else None
    displayed_free = [int(n.replace(",", "")) for n in re.findall(r"([0-9,]+) free bytes on drive C:", screen)]
    if program["id"] == "pctools":
        displayed_free.extend(int(n) for n in re.findall(r"(\d+)=bytes Free", screen))
    disk_free_valid = all(n == free_bytes for n in displayed_free)
    artifacts_valid = True
    artifact_sha256 = None
    if program.get("verify_zip"):
        try:
            data = image_file(disk, "::APPS/" + program["package"].upper() + "/" + program["verify_zip"])
            (directory / program["verify_zip"]).write_bytes(data)
            artifact_sha256 = hashlib.sha256(data).hexdigest()
            expected = image_file(disk, "::APPS/" + program["package"].upper() + "/SAMPLE.TXT")
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                artifacts_valid = archive.namelist() == ["SAMPLE.TXT"] and archive.read("SAMPLE.TXT") == expected
        except (subprocess.CalledProcessError, zipfile.BadZipFile, KeyError):
            artifacts_valid = False
    return {"directory": str(directory.relative_to(output)), "screen": screen,
            "artifacts_valid": artifacts_valid, "artifact_sha256": artifact_sha256,
            "ready": ready, "free_bytes": free_bytes, "disk_free_valid": disk_free_valid,
            "video_attributes_sha256": hashlib.sha256((directory / "vram.bin").read_bytes()[1::2]).hexdigest(),
            "executable_sha256": hashlib.sha256(image_file(disk, "::APPS/" + program["package"].upper() + "/" + program["command"].split()[0])).hexdigest()}


def normalize(program, screen):
    if program == "d86":
        # Empty debuggee segments are allocated by DOS, so their addresses
        # vary with kernel size. Preserve relationships to CS; BP is explicitly
        # initialized by the manifest instead of masking an undefined value.
        match = re.search(r"\bCS ([0-9A-F]{4})", screen)
        if match:
            segment = int(match.group(1), 16)
            screen = re.sub(r"\b(CS|DS|ES|SS|DX) ([0-9A-F]{4})",
                lambda m: f"{m[1]} <CS{(int(m[2], 16) - segment):+d}>", screen)
    if program == "asa57":
        screen = re.sub(r"(V57 Free:100%\[)\d+k\]", r"\1<MEM>k]", screen)
        screen = re.sub(r"\d{2}:\d{2}:\d{2} [ap]m(?=\s*$)", "<CLOCK>", screen)
    if program == "pctools":
        screen = re.sub(r"\d+(?==bytes Free)", "<FREE>", screen)
        screen = re.sub(r"\d{2}:\d{2}[ap]m", "<CLOCK>", screen)
    if program == "rar":
        screen = re.sub(r"(Memory in use +)\d+ Kb", r"\1<MEM> Kb", screen)
    if program == "qedit":
        screen = re.sub(r"(?m)^(L 1 +C 1 +IA +)\d+k", r"\1<MEM>k", screen)
    if program == "dn":
        lines = screen.splitlines()
        lines[0] = re.sub(r"\d{2}:\d{2}:\d{2}", "<CLOCK>", lines[0])
        screen = "\n".join(lines)
        screen = re.sub(r"[0-9,]+(?= free bytes on drive C:)", "<FREE>", screen)
    return screen


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--retail-image", type=Path, required=True)
    p.add_argument("--fork-floppy", type=Path, default=ROOT / "out/floppy.img")
    p.add_argument("--cache", type=Path, default=ROOT / ".reference/dos-apps")
    p.add_argument("--output", type=Path)
    p.add_argument("--program", action="append")
    p.add_argument("--profile", action="append", choices=PROFILES)
    p.add_argument("--seconds", type=float, default=40)
    p.add_argument("--prepare-only", action="store_true")
    p.add_argument("--record-baseline", type=Path, help="save compact, redistributable results without media or screen text")
    args = p.parse_args()
    manifest = json.loads((ROOT / "tests/dos_app_smoke.json").read_text())
    unknown = set(args.program or []) - {app["id"] for app in manifest["programs"]}
    if unknown:
        p.error("unknown program(s): " + ", ".join(sorted(unknown)))
    if args.seconds <= 1:
        p.error("--seconds must allow more than one second for settling")
    if args.output and args.output.exists() and any(args.output.iterdir()):
        p.error("--output must be an empty directory")
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="dos-app-smoke-", dir=ROOT / "out"))
    output.mkdir(parents=True, exist_ok=True)
    print(f"Evidence: {output}", flush=True)
    args.cache.mkdir(parents=True, exist_ok=True)
    provenance = {"qemu_version": subprocess.check_output(["qemu-system-i386", "--version"]).decode().splitlines()[0], "block_chaining": False, "retail_image_sha256": sha(args.retail_image), "fork_floppy_sha256": sha(args.fork_floppy), "packages": {}, "systems": {}}
    fork = build_fork(args.retail_image.resolve(), args.fork_floppy.resolve(), output)
    bases = {}
    for label, source in (("stock", args.retail_image), ("fork", fork)):
        base = output / (label + "-base.img")
        shutil.copyfile(source, base)
        bases[label] = base
        provenance["systems"][label] = {name: hashlib.sha256(image_file(base, "::" + name)).hexdigest() for name in ("IO.SYS", "MSDOS.SYS", "COMMAND.COM", "DOS/HIMEM.SYS", "DOS/EMM386.EXE")}
        run(["mmd", "-i", f"{base}@@{partition_offset(base)}", "::APPS"])
    for package in manifest["packages"]:
        directory, details = package_files(package, args.cache)
        provenance["packages"][package["id"]] = details
        (directory / "SAMPLE.TXT").write_bytes(b"DOS application startup comparison\r\nSame input on both systems.\r\n")
        for base in bases.values():
            spec = f"{base}@@{partition_offset(base)}"
            target = "::APPS/" + package["id"].upper()
            run(["mmd", "-i", spec, target])
            run(["mcopy", "-s", "-m", "-i", spec, *sorted(directory.iterdir()), target + "/"])
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    if args.prepare_only:
        return
    results = []
    failed = False
    with ThreadPoolExecutor(max_workers=2) as pool:
        for program in manifest["programs"]:
            if args.program and program["id"] not in args.program:
                continue
            for profile in args.profile or PROFILES:
                futures = {label: pool.submit(capture, base, program, profile, label, output, args.seconds) for label, base in bases.items()}
                pair = {label: future.result() for label, future in futures.items()}
                assert pair["stock"]["executable_sha256"] == pair["fork"]["executable_sha256"]
                diff = "".join(difflib.unified_diff(pair["stock"]["screen"].splitlines(True), pair["fork"]["screen"].splitlines(True), fromfile="stock", tofile="fork"))
                (output / (program["id"] + "-" + profile + ".diff")).write_text(diff)
                normalized = {label: normalize(program["id"], data["screen"]) for label, data in pair.items()}
                normalized_diff = "".join(difflib.unified_diff(normalized["stock"].splitlines(True), normalized["fork"].splitlines(True), fromfile="stock", tofile="fork"))
                (output / (program["id"] + "-" + profile + "-normalized.diff")).write_text(normalized_diff)
                attributes_equal = pair["stock"]["video_attributes_sha256"] == pair["fork"]["video_attributes_sha256"]
                passed = all(data["ready"] and data["disk_free_valid"] and data["artifacts_valid"] for data in pair.values()) and not normalized_diff and attributes_equal and pair["stock"]["artifact_sha256"] == pair["fork"]["artifact_sha256"]
                failed |= not passed
                result = {"program": program["id"], "profile": profile, "passed": passed, "text_identical": not diff,
                          "normalized_text_identical": not normalized_diff, "attributes_identical": attributes_equal, "captures": pair}
                results.append(result)
                (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
                print(program["id"], profile, "PASS" if passed else "FAIL (review required)", "identical text" if not diff else "raw text differs", flush=True)
    report = ["# DOS application startup comparison", "", "QEMU pc / 486 / 8 MiB, fixed RTC, private FAT16 images; same app files and CONFIG.SYS per pair.", "",
              "LOW: conventional DOS; XMS: HIMEM + DOS=HIGH; HIGH: HIMEM + EMM386 2048 RAM + DOS=HIGH,UMB.", "",
              "Startup smoke tests only. Candidate features in the manifest are selection rationale, not measured INT 21h coverage.", "",
              "Normalization covers documented memory/address fields, clocks, and independently verified free disk space; see tests/DOS-APP-SMOKE.md.", "",
              "| Program | Profile | Ready stock/fork | Raw text equal | Normalized text equal | Attributes equal | Result |",
              "| --- | --- | --- | --- | --- | --- | --- |"]
    for r in results:
        report.append(f"| {r['program']} | {r['profile']} | {r['captures']['stock']['ready']}/{r['captures']['fork']['ready']} | {r['text_identical']} | {r['normalized_text_identical']} | {r['attributes_identical']} | {'PASS' if r['passed'] else 'FAIL'} |")
    (output / "report.md").write_text("\n".join(report) + "\n")
    if args.record_baseline:
        baseline = {
            "schema": 1,
            "recorded_at": datetime.now(timezone.utc).isoformat(),
            "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip(),
            "runner_sha256": sha(__file__),
            "manifest_sha256": sha(ROOT / "tests/dos_app_smoke.json"),
            "scope": "startup only" + (", plus small child-process artifact checks"
                if any(app.get("verify_zip") for app in manifest["programs"]
                       if not args.program or app["id"] in args.program) else ""),
            "hardware": {"machine": "pc", "cpu": "486", "ram_mib": 8, "rtc": "1995-01-02T12:00:00"},
            "provenance": provenance,
            "profiles": {name: PROFILES[name] for name in args.profile or PROFILES},
            "results": [],
        }
        for result in results:
            record = {key: value for key, value in result.items() if key != "captures"}
            record["captures"] = {}
            for label, data in result["captures"].items():
                capture_record = {key: value for key, value in data.items() if key not in ("directory", "screen")}
                capture_record["screen_sha256"] = hashlib.sha256(data["screen"].encode()).hexdigest()
                record["captures"][label] = capture_record
            baseline["results"].append(record)
        args.record_baseline.parent.mkdir(parents=True, exist_ok=True)
        args.record_baseline.write_text(json.dumps(baseline, indent=2) + "\n")
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
