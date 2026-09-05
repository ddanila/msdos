#!/usr/bin/env python3
"""Execute linked BIOS services in allocated HMA with private low fixtures."""
from pathlib import Path
import os
import shutil
import struct
import subprocess
import tempfile

from build_bios_high_payload import ROOT, build, run


def main():
    scratch = Path(tempfile.mkdtemp(prefix="bios-payload-runtime-", dir=ROOT / "out"))
    manifest = build(scratch)
    layout = scratch / "layout.bin"
    run([ROOT / "bin/jwasm-bin", f"-I{ROOT / 'src/INC'}", f"-Fo{layout}",
         ROOT / "tests/bios_payload_layout_masm.asm"], ROOT)
    fields = struct.unpack("<7H", layout.read_bytes())
    definitions = [f"BDS_{name} equ {value}" for name, value in
                   zip(("DRIVENUM", "FLAGS", "TRACK", "TIM_LO", "TIM_HI", "FIXED", "DRIVELET"), fields)]
    definitions += [f"LOW_{name} equ {value}" for name, value in manifest["low_bindings"].items()]
    definitions += [f"SLOT_{name} equ {slot['offset']}" for name, slot in manifest["runtime_slots"].items()]
    definitions += [f"ENTRY_READ_SECTOR equ {manifest['exports']['READ_SECTOR']}",
                    f"ENTRY_NEAR_GATE equ {manifest['exports']['BIOS_HMA_ENTER_NEAR']}",
                    f"ENTRY_HARDERR2 equ {manifest['exports']['HARDERR2']}",
                    f"ENTRY_REMOVABLE equ {manifest['exports']['DSK$REM']}",
                    f"ENTRY_IOCTL equ {manifest['exports']['GENERIC$IOCTL']}",
                    f"ENTRY_MOVE equ {manifest['exports']['MOVE']}",
                    f"CPU_PATCH_OFFSET equ {manifest['boot_patches']['DOUBLEWORDMOV']['offset']}",
                    f"CPU_PATCH_SIZE equ {manifest['boot_patches']['DOUBLEWORDMOV']['size']}",
                    f"FIXUP_COUNT equ {len(manifest['offset_fixups'])}"]
    traps = [slot["offset"] for name, slot in manifest["runtime_slots"].items()
             if slot["size"] == 4 and name not in ("BIOS_SERVICE_INT13_GATE", "BIOS_SERVICE_INT1A_GATE")]
    definitions += [f"TRAP_SLOT_COUNT equ {len(traps)}"]
    (scratch / "payload-defs.inc").write_text("\n".join(definitions) + "\n")
    tables = ["fixups:", "dw " + ",".join(map(str, manifest["offset_fixups"])),
              "trap_slots:", "dw " + ",".join(map(str, traps))]
    (scratch / "payload-tables.inc").write_text("\n".join(tables) + "\n")
    modes = (("success", 0, 1, 0, 0), ("retry", 2, 3, 2, 0),
             ("error", 3, 3, 3, 1), ("word-copy", 0, 1, 0, 0),
             ("nonlocal-unwind", 0, 1, 0, 1),
             ("device-removable", 0, 0, 0, 0), ("device-fixed", 0, 0, 0, 0),
             ("device-ioctl-error", 0, 0, 0, 0), ("device-missing-a20", 0, 0, 0, 0),
             ("partial-copy-patch", 0, 1, 0, 0), ("missing-fixups", 0, 1, 0, 0),
             ("missing-entry-a20", 0, 1, 0, 0))
    env = {**os.environ, "MTOOLS_SKIP_CHECK": "1"}
    for name, failures, reads, resets, error in modes:
        probe = scratch / f"{name}.com"
        options = [f"-DFAIL_READS={failures}", f"-DEXPECTED_READS={reads}",
                   f"-DEXPECTED_RESETS={resets}", f"-DEXPECTED_ERROR={error}"]
        if name == "missing-fixups":
            options.append("-DOMIT_FIXUPS")
        if name == "missing-entry-a20":
            options.append("-DOMIT_ENTRY_A20")
        if name == "nonlocal-unwind":
            options.append("-DTEST_UNWIND")
        if name.startswith("device-"):
            device = 3 if name == "device-ioctl-error" else 2 if name == "device-fixed" else 1
            options.append(f"-DTEST_DEVICE={device}")
            if name == "device-missing-a20":
                options.append("-DOMIT_ENTRY_A20")
        copy_mode = 1 if name == "word-copy" else 2 if name == "partial-copy-patch" else 0
        options.append(f"-DCOPY_MODE={copy_mode}")
        run(["nasm", "-f", "bin", f"-I{scratch}/", f"-I{ROOT / 'src/BIOS'}/", *options,
             ROOT / "tests/bios_payload_probe.asm", "-o", probe], ROOT)
        image = scratch / f"{name}.img"
        shutil.copyfile(ROOT / "out/floppy.img", image)
        subprocess.run(["mcopy", "-o", "-i", str(image), str(probe), "::PAYLOAD.COM"],
                       env=env, check=True)
        for path, data in (("CONFIG.SYS", "DEVICE=HIMEM.SYS /TESTMEM:OFF\r\nDOS=HIGH\r\n"),
                           ("AUTOEXEC.BAT", "@ECHO OFF\r\nCTTY AUX\r\nPAYLOAD.COM\r\n")):
            subprocess.run(["mcopy", "-o", "-i", str(image), "-", f"::{path}"],
                           input=data.encode(), env=env, check=True)
        log = scratch / f"{name}.log"
        with log.open("wb") as stream:
            try:
                subprocess.run(["qemu-system-i386", "-display", "none", "-monitor", "none",
                                "-machine", "pc", "-cpu", "486", "-m", "8", "-boot", "a",
                                "-serial", "stdio", "-no-reboot",
                                "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04", "-drive",
                                f"if=floppy,index=0,format=raw,file={image},cache=writethrough"],
                               stdout=stream, stderr=subprocess.STDOUT, timeout=35)
            except subprocess.TimeoutExpired:
                pass
        captured = log.read_bytes()
        passed = b"BIOS_PAYLOAD_PASS" in captured
        negative = name in ("missing-fixups", "partial-copy-patch", "missing-entry-a20",
                            "device-missing-a20")
        if (b"BIOS_PAYLOAD_READY" not in captured or passed == negative
                or (name == "partial-copy-patch" and b"BIOS_PAYLOAD_FAIL" not in captured)
                or (passed and b"BIOS_PAYLOAD_FAIL" in captured)):
            raise RuntimeError(f"FAIL {name}; evidence: {log}\n{captured.decode(errors='replace')}")
        print(f"PASS {name}: {log}", flush=True)


if __name__ == "__main__":
    main()
