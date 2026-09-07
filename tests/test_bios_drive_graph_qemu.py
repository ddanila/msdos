#!/usr/bin/env python3
"""Retire boot descriptor templates, qualify the packed graph and measure VC."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

from build_bios_low_image import build
from capture_vc_memory_comparison import capture, image_file, parse_capture
from report_dos_bios_residency import parse_map
from test_dos_char_retirement_qemu import install, probe
from test_umb_subpage_composition import xms_summary

ROOT = Path(__file__).resolve().parents[1]


def graph(work, image, two_disks, no_floppy=False):
    name = "no-floppy" if no_floppy else "two" if two_disks else "one"
    result = subprocess.run([
        sys.executable, ROOT / "tests/capture_bios_descriptor_graph.py", image,
        work / "packed", work / "MSDOS.MAP", *(["--two-disks"] if two_disks else []),
        *(["--no-floppy"] if no_floppy else [])],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True, timeout=65)
    (work / f"graph-{name}.log").write_bytes(result.stdout)
    directory = Path(result.stdout.decode().splitlines()[0].removeprefix("Artifacts: "))
    record = json.loads((directory / "graph.json").read_text())
    memory = (directory / "memory.bin").read_bytes()
    _, symbols = parse_map(work / "packed/msBIO.map")
    symbols = {key.upper(): value for key, value in symbols.items()}
    word = lambda offset: struct.unpack_from("<H", memory, 0x700 + offset)[0]
    low_end = 16 * word(symbols["BIOS_PERMANENT_END"])
    assert record["dos_low_segment"] == 0x70 + low_end // 16
    assert symbols["BIOS_BDS_TEMPLATES_START"] >= low_end
    first = record["bds"][0]["offset"]
    for index, row in enumerate(record["bds"]):
        assert row["segment"] == 0x70 and row["offset"] == first + index * 100
        assert row["offset"] + 100 <= low_end
        assert word(symbols["DSKDRVS"] + 2 * index) == row["offset"] + 6
    overflow = word(symbols["COMPACTDPBSTORAGE"])
    assert overflow == first + len(record["bds"]) * 100
    for index, row in enumerate(record["dpbs"][2:]):
        assert row["segment"] == 0x70 and row["offset"] == overflow + 33 * index
    assert 0 <= low_end - (overflow + 33 * len(record["dpbs"][2:])) < 16
    record.update(evidence=str(directory), retained_bios_bytes=low_end)
    print(f"Packed {name}-disk graph: {len(record['bds'])} drives, BIOS {low_end} bytes", flush=True)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="completed, unpacked composed image")
    args = parser.parse_args()
    work = Path(tempfile.mkdtemp(prefix="bios-graph-retirement-", dir=ROOT / "out"))
    print(f"Artifacts: {work}", flush=True)
    assert image_file(args.image, "::MSDOS.SYS") == (ROOT / "src/DOS/MSDOS.SYS").read_bytes()
    for name in ("MSDOS.SYS", "MSDOS.MAP"):
        shutil.copyfile(ROOT / "src/DOS" / name, work / name)
    provider = work / "EMM386.EXE"
    provider.write_bytes(image_file(args.image, "::DOS/EMM386.EXE"))
    options = dict(early=True, tail_body=True, rebase=True, compact=True,
                   high_cds=True, dispatch=True, characters=True, retire_characters=True,
                   pack_headers=True, retire_media=True, paired_provider=provider)
    build(work / "control", **options)
    assert (work / "control/IO.SYS").read_bytes() == image_file(args.image, "::IO.SYS")
    build(work / "packed", pack_drive_graph=True, **options)
    manifests = [json.loads((work / name / "low.json").read_text()) for name in ("control", "packed")]
    assert manifests[0]["embedded_payload_bytes"] == manifests[1]["embedded_payload_bytes"]
    packed = work / "input-packed.img"
    shutil.copyfile(args.image, packed)
    install(packed, "IO.SYS", (work / "packed/IO.SYS").read_bytes())
    unchanged = {}
    for name in ("CONFIG.SYS", "AUTOEXEC.BAT", "MSDOS.SYS", "COMMAND.COM", "DOS/COMMAND.COM",
                 "DOS/HIMEM.SYS", "DOS/EMM386.EXE", "VC/VC.COM"):
        data = image_file(args.image, "::" + name)
        assert image_file(packed, "::" + name) == data
        unchanged[name] = hashlib.sha256(data).hexdigest()
    graphs = {"one": graph(work, packed, False), "two": graph(work, packed, True),
              "no-floppy": graph(work, packed, False, no_floppy=True)}
    for source, target in (("int21_fcb_probe.asm", "I21FCB.COM"),
                           ("bios_external_bds_probe.asm", "BDSGRAPH.COM"),
                           ("qemu_exit.asm", "QEXIT.COM"), ("memory_ceiling_probe.asm", "CEILING.COM")):
        subprocess.run(["nasm", "-f", "bin", ROOT / "tests" / source,
                        "-o", work / target], check=True)
    probe_image = work / "input-probes.img"
    shutil.copyfile(packed, probe_image)
    install(probe_image, "BDSGRAPH.COM", (work / "BDSGRAPH.COM").read_bytes())
    for name, mode in (("high", "HIGH"), ("standalone-low", "LOW")):
        assert probe(work, probe_image, name, mode, before=b"BDSGRAPH.COM\r\n")
        assert b"BIOS_EXTERNAL_BDS_PASS" in (work / f"fcb-{name}.log").read_bytes()
    results = {}
    for name, image in (("control", args.image), ("packed", packed)):
        serial, screen = capture(name, image.resolve(), work, work / "CEILING.COM")
        results[name] = parse_capture(serial, screen)
        results[name]["xms"] = xms_summary(serial.read_text(encoding="latin-1"))
        print(f"Measured {name}: {results[name]['largest']} conventional / "
              f"{results[name]['upper_free']} UMB / {results[name]['xms']} XMS", flush=True)
    gain = results["packed"]["largest"] - results["control"]["largest"]
    assert gain > 0 and gain == 3232 - graphs["one"]["retained_bios_bytes"]
    assert results["packed"]["upper_free"] == results["control"]["upper_free"]
    assert results["packed"]["xms"] is not None
    assert results["packed"]["xms"] == results["control"]["xms"]
    (work / "results.json").write_text(json.dumps(dict(results=results, graphs=graphs,
        unchanged_sha256=unchanged, composed_gain=gain,
        input_sha256={"control": hashlib.sha256(args.image.read_bytes()).hexdigest(),
                      "packed": hashlib.sha256(packed.read_bytes()).hexdigest()}), indent=2) + "\n")
    print(f"PASS: packed graph retirement recovers {gain} conventional bytes", flush=True)


if __name__ == "__main__":
    main()
