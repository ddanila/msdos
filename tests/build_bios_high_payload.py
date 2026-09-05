#!/usr/bin/env python3
"""Link the isolated BIOS body against pinned low offsets; never install it.

The zero-valued runtime slots require a validated installer. Generated output
is a development artifact, not a bootable or directly callable BIOS image.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import runpy
import subprocess
import tempfile

from report_dos_bios_residency import parse_map

ROOT = Path(__file__).resolve().parent.parent
SLOT_TARGETS = {
    "BIOS_SERVICE_LOW_SEGMENT": (2, "resident low BIOS segment"),
    "BIOS_SERVICE_ORIG13_OFFSET": (2, "ORIG13"),
    "BIOS_SERVICE_NEXT2F_OFFSET": (2, "NEXT2F_13"),
    "BIOS_SERVICE_INT13_GATE": (4, "BIOS_HMA_INT13"),
    "BIOS_SERVICE_INT1A_GATE": (4, "BIOS_HMA_INT1A"),
    "BIOS_SERVICE_SAVED_VECTOR_GATE": (4, "BIOS_HMA_SAVED_VECTOR"),
    "BIOS_SERVICE_CHAIN_VECTOR_GATE": (4, "BIOS_HMA_CHAIN_VECTOR"),
    "BIOS_SERVICE_NEAR_CALL_GATE": (4, "BIOS_HMA_NEAR_CALL"),
    "BIOS_LOW_BUSY_ENTRY": (4, "BUS$EXIT"),
    "BIOS_LOW_CMDERR_ENTRY": (4, "CMDERR"),
    "BIOS_LOW_ERRCNT_ENTRY": (4, "ERR$CNT"),
    "BIOS_LOW_ERREXIT_ENTRY": (4, "ERR$EXIT"),
    "BIOS_LOW_EXIT_ENTRY": (4, "EXIT"),
    "BIOS_LOW_GETBP": (2, "GETBP"),
    "BIOS_LOW_HASCHANGE": (2, "HASCHANGE"),
    "BIOS_LOW_MEDIA_IDS": (2, "Mov_Media_IDs"),
    "BIOS_LOW_SET_CHANGED": (2, "SET_CHANGED_DL"),
    "BIOS_LOW_SWPDSK": (2, "SWPDSK"),
    "BIOS_LOW_CHECKIO_RESULT": (2, "BIOS_CHECKIO_RESULT"),
    "BIOS_LOW_CHECKLATCH_RESULT": (2, "BIOS_CHECKLATCH_RESULT"),
}


def run(command, cwd):
    result = subprocess.run([str(arg) for arg in command], cwd=cwd, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)


def build(output):
    output.mkdir(parents=True, exist_ok=True)
    low_map = ROOT / "src/BIOS/msBIO.map"
    _, low_symbols = parse_map(low_map)
    low_symbols = {name.upper(): value for name, value in low_symbols.items()}
    with tempfile.TemporaryDirectory(prefix="msdos-high-link-") as scratch:
        scratch = Path(scratch)
        listing = scratch / "body.lst"
        body = scratch / "body.obj"
        run([ROOT / "bin/jwasm-masm",
             f"-I. -I../INC -DBIOS_SERVICE_ISOLATED=1 -Fl{listing}",
             f"MSDISK.ASM,{body};"], ROOT / "src/BIOS")
        externals = {}
        for line in listing.read_text(encoding="latin-1").splitlines():
            match = re.match(r"^([\w$]+)\s+(?:\.\s+)*\s*(.*?)\s+External\s*$", line)
            if match:
                name, description = match.groups()
                externals[name.upper()] = 4 if description.startswith("DWord") else 2
        if not externals:
            raise ValueError("no external symbols parsed from isolated listing")
        slots = {name: size for name, size in externals.items()
                 if name.startswith(("BIOS_SERVICE_", "BIOS_LOW_"))}
        if slots != {name: spec[0] for name, spec in SLOT_TARGETS.items()}:
            raise ValueError("runtime imports changed; review slot widths and target contracts")
        low = {name: low_symbols[name] for name in externals if name not in slots}
        definitions = [".8086"]
        for name, value in sorted(low.items()):
            definitions += [f"PUBLIC {name}", f"{name} EQU {value}"]
        definitions += ["BIOSHIGH SEGMENT BYTE PUBLIC 'BIOSHIGH'"]
        for name, size in sorted(slots.items()):
            definitions += [f"PUBLIC {name}", f"{name} {'DD' if size == 4 else 'DW'} 0"]
        definitions += ["PUBLIC BIOS_PAYLOAD_END", "BIOS_PAYLOAD_END LABEL BYTE",
                        "BIOSHIGH ENDS", "END"]
        source = scratch / "bindings.asm"
        source.write_text("\n".join(definitions) + "\n")
        bindings = scratch / "bindings.obj"
        run([ROOT / "bin/jwasm-masm", "", f"{source},{bindings};"], ROOT)
        # Use the configured native linker, without Microsoft-LINK syntax translation.
        linker = runpy.run_path(str(ROOT / "bin/wlink"))["wlink_bin"]()
        payload = output / "bios-high.bin"
        linked_map = output / "bios-high.map"

        def link(origin, destination, map_path):
            prefix_source = scratch / "prefix.asm"
            prefix_source.write_text("BIOSHIGH SEGMENT BYTE PUBLIC 'BIOSHIGH'\n"
                                     f"DB {origin} DUP (0)\nBIOSHIGH ENDS\nEND\n")
            prefix = scratch / "prefix.obj"
            run([ROOT / "bin/jwasm-masm", "", f"{prefix_source},{prefix};"], ROOT)
            run([linker, "format", "raw", "bin", "option", "quiet", "option", "nocaseexact",
                 "option", "nofarcalls", "option", f"map={map_path}", "name", destination,
                 "file", f"{prefix},{body},{bindings}"], ROOT)
            raw = destination.read_bytes()
            if any(raw[:origin]):
                raise ValueError("linker prefix changed")
            return raw[origin:]

        data = link(0, payload, linked_map)
        symbols = {match[2].upper(): int(match[1], 16)
                   for line in linked_map.read_text().splitlines()
                   if (match := re.match(r"^([0-9a-fA-F]{8})[*+]?\s+([\w$]+)\s*$", line))}
        if symbols["BIOS_SERVICE_START"] != 0 or symbols["BIOS_PAYLOAD_END"] != len(data):
            raise ValueError("linker output does not match isolated payload boundaries")
        runtime = {name: {"offset": symbols[name], "size": size, "target": SLOT_TARGETS[name][1]}
                   for name, size in slots.items()}
        for slot in runtime.values():
            if any(data[slot["offset"]:slot["offset"] + slot["size"]]):
                raise ValueError("unbound runtime slot is not zero")
        shifted = link(1, scratch / "shift.bin", scratch / "shift.map")
        relocations = offset_fixups(data, shifted)
        if any(int.from_bytes(data[offset:offset + 2], "little") >= len(data)
               for offset in relocations):
            raise ValueError("internal offset points outside payload")
        # Independent even, odd and page-crossing origins must reproduce the
        # linker's exact bytes, not merely its exported entry addresses.
        origins = (16, 0x123, 0x4000)
        for origin in origins:
            expected = link(origin, scratch / "shift.bin", scratch / "shift.map")
            if rebase(data, relocations, origin) != expected:
                raise ValueError(f"offset-fixup model disagrees with linker at {origin:04x}")
        manifest = {"installed": False, "runtime_bindings_required": True,
                    "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data),
                    "service_bytes": symbols["BIOS_SERVICE_END"],
                    "low_map_sha256": hashlib.sha256(low_map.read_bytes()).hexdigest(),
                    "low_image_sha256": hashlib.sha256((ROOT / "src/BIOS/IO.SYS").read_bytes()).hexdigest(),
                    "low_bindings": low, "runtime_slots": runtime,
                    "offset_fixups": relocations, "verified_origins": [0, 1, *origins],
                    "exports": {name: offset for name, offset in symbols.items()
                                if name not in low and name not in slots},
                    "warning": "Rebase internal offset words and bind every runtime slot before use; low entry gates remain required."}
        (output / "bios-high.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        print(f"Linked {len(data)} bytes ({manifest['service_bytes']} service bytes); "
              f"{len(runtime)} unbound runtime slots; {len(relocations)} checked offset fixups.")
        return manifest


def offset_fixups(base, shifted):
    """Infer offset16 relocations at origin+1; reject any other byte change.

    A +1 word relocation always changes its first byte, including carry. Later
    independent links validate this model; this is not a general OMF parser.
    """
    if len(base) != len(shifted):
        raise ValueError("origin changed payload length")
    offsets = []
    index = 0
    while index < len(base):
        if base[index] == shifted[index]:
            index += 1
            continue
        if index + 2 > len(base):
            raise ValueError("non-word change at payload end")
        old = int.from_bytes(base[index:index + 2], "little")
        new = int.from_bytes(shifted[index:index + 2], "little")
        if new != old + 1:
            raise ValueError("link difference is not an offset16 relocation")
        offsets.append(index)
        index += 2
    return offsets


def rebase(data, offsets, origin):
    if origin < 0 or origin + len(data) > 0x10000:
        raise ValueError("payload exceeds segment")
    result = bytearray(data)
    previous = -2
    for offset in offsets:
        if offset < previous + 2 or offset + 2 > len(data):
            raise ValueError("invalid/overlapping offset fixup")
        value = int.from_bytes(data[offset:offset + 2], "little") + origin
        if value > 0xffff:
            raise ValueError("offset fixup overflows")
        result[offset:offset + 2] = value.to_bytes(2, "little")
        previous = offset
    return bytes(result)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    build(parser.parse_args().output.resolve())
