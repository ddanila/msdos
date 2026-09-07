#!/usr/bin/env python3
"""Rebuild mode-policy modules against a frozen composed manager build."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DEFINES = ("-DEMM_INIT_PHASE_TRACE -DUMB_SUBPAGE_DISCOVERY -DUMB_SUBPAGE_MAPPING "
    "-DEMM_COMMON_XMS_TEST -DEMM_BOOTSTRAP_OWNER_TEST -DEMM_UMB_OWNER_TEST "
    "-DEMM_UMB_RESULTS_TEST -DEMM_XMS_COPY_TEST -DEMM_XMS_OWNER_TEST "
    "-DEMM_AUTHORITATIVE_OWNER_TEST -DEMM_XMS_OWNER_TRACE -DEMM_BOOTSTRAP_XMS_HANDLES=32 "
    "-DEMM_BOOTSTRAP_EXPECT_HMA -DEMM_BOOTSTRAP_STAGE_TEST -DEMM_TABLE_LAYOUT_TRACE "
    "-DEMM_HIGH_TABLES -DEMM_SPLIT_PREPARE -DEMM_DEFER_PROVIDER -DPROVIDER_REBASE")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frozen", type=Path)
    parser.add_argument("--image", type=Path, help="rebuild the paired BIOS loader and compose the candidate")
    parser.add_argument("--measure", action="store_true", help="capture the paired before/after VC and MEM census")
    parser.add_argument("--compact-tracks", action="store_true", help="retain R,N pairs and materialize firmware format tuples")
    args = parser.parse_args()
    if args.measure and not args.image:
        parser.error("--measure requires --image")
    work = Path(tempfile.mkdtemp(prefix="emm-mode-guard-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    shutil.copytree(args.frozen / "MEMM", work / "MEMM")
    shutil.copytree(args.frozen / "INC", work / "INC")
    build = work / "MEMM/MEMM"
    original = (build / "EMM386.EXE").read_bytes()
    with (work / "build.log").open("w") as log:
        for fresh in (False, True):
            for module in ("INIT", "EMM", "ELIMFUNC"):
                if fresh:
                    shutil.copyfile(ROOT / f"src/MEMM/MEMM/{module}.ASM", build / f"{module}.ASM")
                flags = DEFINES if module == "INIT" else ""
                subprocess.run([ROOT / "bin/jwasm-masm",
                    f"-Mx -t -DI386 -DNoBugMode -DNOHIMEM {flags} -I. -I../EMM",
                    f"{module}.ASM,{module}.OBJ;"], cwd=build, stdout=log, stderr=log, check=True)
            subprocess.run([ROOT / "bin/wlink", "/NOI /PACKDATA:1 @EMM386.LNK"],
                           cwd=build, stdout=log, stderr=log, check=True)
            if not fresh:
                assert (build / "EMM386.EXE").read_bytes() == original, "frozen reconstruction changed"
    print(build / "EMM386.EXE", flush=True)
    print(hashlib.sha256((build / "EMM386.EXE").read_bytes()).hexdigest(), flush=True)
    if args.image:
        from build_bios_low_image import build as build_bios
        from test_dos_char_retirement_qemu import install
        build_bios(work / "bios", early=True, tail_body=True, rebase=True, compact=True,
            high_cds=True, dispatch=True, characters=True, retire_characters=True,
            pack_headers=True, retire_media=True, pack_drive_graph=True,
            high_stack_pool=True, retire_clock=True, retire_mux=True,
            paired_provider=build / "EMM386.EXE", compact_tracks=args.compact_tracks)
        disk = work / "input.img"
        shutil.copyfile(args.image, disk)
        install(disk, "IO.SYS", (work / "bios/IO.SYS").read_bytes())
        install(disk, "DOS/EMM386.EXE", (build / "EMM386.EXE").read_bytes())
        print(disk, flush=True)
        if args.measure:
            from capture_vc_memory_comparison import capture, parse_capture, image_file
            from test_umb_subpage_composition import xms_summary
            ceiling = work / "CEILING.COM"
            subprocess.run(["nasm", "-f", "bin", ROOT / "tests/memory_ceiling_probe.asm",
                            "-o", ceiling], check=True)
            results = dict(unchanged_sha256={})
            for name in ("MSDOS.SYS", "COMMAND.COM", "DOS/COMMAND.COM", "CONFIG.SYS",
                         "AUTOEXEC.BAT", "DOS/HIMEM.SYS", "VC/VC.COM"):
                data = image_file(args.image, "::" + name)
                assert data == image_file(disk, "::" + name), name
                results["unchanged_sha256"][name] = hashlib.sha256(data).hexdigest()
            for label, source in (("after", disk), ("before", args.image)):
                serial, screen = capture(label, source.resolve(), work, ceiling)
                results[label] = parse_capture(serial, screen)
                results[label]["xms"] = xms_summary(serial.read_text(encoding="latin-1"))
                (work / "results.json").write_text(json.dumps(results, indent=2) + "\n")
            assert results["after"]["largest"] >= 618736
            assert results["after"]["upper_free"] >= 47888
            print(json.dumps(results), flush=True)


if __name__ == "__main__":
    main()
