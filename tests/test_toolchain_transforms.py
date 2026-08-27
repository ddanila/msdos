#!/usr/bin/env python3
"""Focused contracts for the native toolchain's compatibility transforms."""

from __future__ import annotations

import runpy
import struct
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def test_jwasm_consumes_dos_sources_directly() -> None:
    with tempfile.TemporaryDirectory(prefix="jwasm-direct-test-") as name:
        directory = Path(name)
        includes = directory / "Includes"
        includes.mkdir()
        (includes / "MixedCase.INC").write_text("included equ 7\n")
        (directory / "MAIN.ASM").write_text(
            ".model tiny\n"
            ".code\n"
            "option nokeyword:<.if .for>\n"
            ".IF macro condition\n"
            "    db included\n"
            "endm\n"
            ".FOR macro reg,assignment,first,direction,last\n"
            "    db first\n"
            "    db last\n"
            "endm\n"
            "include includes/mixedcase.inc\n"
            "start:\n"
            "    .IF <1 EQ 1>\n"
            "    .FOR BX = 2 TO 3\n"
            "end start\n",
            encoding="latin-1",
        )
        subprocess.run(
            [str(ROOT / "bin/jwasm-masm"), "", "MAIN.ASM,MAIN.OBJ;"],
            cwd=directory,
            check=True,
        )
        assert (directory / "MAIN.OBJ").stat().st_size > 0


def test_exe2bin_accepts_compact_mz_headers() -> None:
    with tempfile.TemporaryDirectory(prefix="wlink-header-test-") as name:
        executable = Path(name) / "sample.exe"
        output = Path(name) / "sample.bin"
        header = bytearray(32)
        header[:2] = b"MZ"
        image = b"LOAD-IMAGE"
        total = len(header) + len(image)
        struct.pack_into("<HHHH", header, 2, total, 1, 0, 2)
        struct.pack_into("<H", header, 0x18, 0x1C)
        executable.write_bytes(header + image)
        subprocess.run(
            [str(ROOT / "bin/exe2bin"), str(executable), str(output)],
            check=True,
        )
        assert output.read_bytes() == image


def test_exefix_contract() -> None:
    with tempfile.TemporaryDirectory(prefix="exefix-test-") as name:
        executable = Path(name) / "sample.exe"
        data = bytearray(32)
        data[:2] = b"MZ"
        struct.pack_into("<HH", data, 10, 0x1111, 0x2222)
        executable.write_bytes(data)
        subprocess.run(
            [str(ROOT / "bin/exefix"), str(executable), "1", "1"],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        result = executable.read_bytes()
        assert struct.unpack_from("<HH", result, 10) == (1, 1)
        assert result[:10] == data[:10] and result[14:] == data[14:]


def test_exepack_fix_contract() -> None:
    module = runpy.run_path(str(ROOT / "bin/fix-exepack"))
    error = module["ERROR_SEQ"]
    message = module["PACKED_STR"]
    old_stub = b"\x90" * (258 - len(error) - len(message)) + error + message
    header = bytearray(32)
    header[:2] = b"MZ"
    struct.pack_into("<HH", header, 8, 2, 0)  # 32-byte MZ header
    struct.pack_into("<HH", header, 20, 16, 0)
    packed = bytearray(16)
    struct.pack_into("<H", packed, 6, 16 + len(old_stub))
    struct.pack_into("<H", packed, 14, 0x4252)
    image = header + packed + old_stub
    struct.pack_into("<HH", image, 2, len(image) % 512, (len(image) + 511) // 512)

    with tempfile.TemporaryDirectory(prefix="exepack-fix-test-") as name:
        executable = Path(name) / "packed.exe"
        executable.write_bytes(image)
        assert module["fix_exepack"](str(executable))
        fixed = executable.read_bytes()
        assert struct.unpack_from("<H", fixed, 20)[0] == 18
        assert module["FIXED_STUB"] in fixed
        assert not module["fix_exepack"](str(executable))
        assert executable.read_bytes() == fixed


def test_wrappers_reject_unknown_options() -> None:
    wlink = runpy.run_path(str(ROOT / "bin/wlink"))
    wlink["validate_options"](["/NOI", "/STACK:4096", "/PACKDATA:1"])
    try:
        wlink["validate_options"](["/TYPO"])
    except SystemExit as error:
        assert "unsupported Microsoft LINK option" in str(error)
    else:
        raise AssertionError("wlink accepted an unknown option")

    result = subprocess.run(
        [str(ROOT / "bin/wcc"), "-QDefinitelyNotAnOption sample.c"],
        text=True,
        capture_output=True,
    )
    assert result.returncode != 0
    assert "unsupported Microsoft C option" in result.stderr


def main() -> None:
    test_jwasm_consumes_dos_sources_directly()
    test_exe2bin_accepts_compact_mz_headers()
    test_exefix_contract()
    test_exepack_fix_contract()
    test_wrappers_reject_unknown_options()
    print("toolchain compatibility transform tests passed")


if __name__ == "__main__":
    main()
