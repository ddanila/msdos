#!/usr/bin/env python3
"""Verify deterministic EDIT archives, license payloads and input rejection."""

import argparse
import json
import re
import runpy
import shutil
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    args = parser.parse_args()
    api = runpy.run_path(str(ROOT / "dwed/tools/package.py"))
    work = Path(tempfile.mkdtemp(prefix="dwed-package-", dir=ROOT / "out"))
    print(work, flush=True)
    first = api["package"](args.build, work / "first")
    second = api["package"](args.build, work / "second")
    assert first == second
    assert (work / "first/EDIT.ZIP").read_bytes() == (
        work / "second/EDIT.ZIP"
    ).read_bytes()
    with zipfile.ZipFile(work / "first/EDIT.ZIP") as archive:
        assert set(archive.namelist()) == set(first["files"])
        for name, expected in first["files"].items():
            assert all(
                re.fullmatch(r"[A-Z0-9_-]{1,8}(?:\.[A-Z0-9]{1,3})?", p)
                for p in name.split("/")
            ), name
            data = archive.read(name)
            assert api["fingerprint"](data) == expected
            assert (work / "first/files" / name).read_bytes() == data
        assert archive.read("EDIT.COM") == (args.build / "DWED.COM").read_bytes()
        assert "DWED.COM" not in archive.namelist()
        assert not any("TEST" in name for name in archive.namelist())
        for source, target in api["NOTICES"].items():
            original = (ROOT / "dwed" / source).read_bytes().replace(b"\r\n", b"\n")
            packaged = archive.read(target)
            assert packaged.replace(b"\r\n", b"\n") == original
            assert b"\n" not in packaged.replace(b"\r\n", b"")
    damaged = work / "damaged-build"
    damaged.mkdir()
    for name in (*api["ARTIFACTS"], "build.json"):
        shutil.copyfile(args.build / name, damaged / name)
    data = bytearray((damaged / "DWED.COM").read_bytes())
    data[0] ^= 1
    (damaged / "DWED.COM").write_bytes(data)
    try:
        api["package"](damaged, work / "rejected")
    except ValueError as error:
        assert "DWED.COM" in str(error)
    else:
        raise AssertionError("tampered launcher was accepted")
    assert not (work / "rejected").exists()
    before = (work / "first/EDIT.ZIP").read_bytes()
    try:
        api["package"](args.build, work / "first")
    except FileExistsError:
        pass
    else:
        raise AssertionError("existing output directory was accepted")
    assert (work / "first/EDIT.ZIP").read_bytes() == before
    result = {
        "passed": True,
        "deterministic_archive": True,
        "dos_names": True,
        "license_text_preserved": True,
        "tampered_input_rejected": True,
        "existing_output_preserved": True,
        "package": first,
    }
    (work / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print("PASS: deterministic package, notices and rejection checks")


if __name__ == "__main__":
    main()
