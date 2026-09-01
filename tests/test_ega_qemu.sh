#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
PROBE="$OUT/ega-api-probe.com"
QEXIT="$OUT/ega-qexit.com"

[[ -f "$BASE" ]] || { echo "missing $BASE; run make deploy" >&2; exit 1; }
nasm -f bin "$ROOT/tests/ega_api_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"

run_case() {
    local name="$1"
    local option="$2"
    local image="$OUT/ega-$name.img"
    local log="$OUT/ega-$name.log"

    cp "$BASE" "$image"
    mcopy -o -i "$image" "$ROOT/src/DEV/EGA/EGA.SYS" ::EGA.SYS
    mcopy -o -i "$image" "$PROBE" ::EGAPROBE.COM
    mcopy -o -i "$image" "$QEXIT" ::QEXIT.COM
    printf 'DEVICE=EGA.SYS %s\r\n' "$option" | mcopy -o -i "$image" - ::CONFIG.SYS
    printf '@ECHO OFF\r\nCTTY AUX\r\nEGAPROBE.COM\r\nIF ERRORLEVEL 1 ECHO EGA_PROBE_FAILED\r\nQEXIT.COM\r\n' |
        mcopy -o -i "$image" - ::AUTOEXEC.BAT
    timeout 30 qemu-system-i386 -display none \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -m 4 -serial stdio \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        </dev/null >"$log" 2>&1 || true
    grep -q 'EGA_API_OK' "$log"
    ! grep -Eq 'EGA_FAIL_|EGA_PROBE_FAILED' "$log"
}

run_case default ""
run_case custom "FUNC=AC"

reject_image="$OUT/ega-invalid.img"
reject_log="$OUT/ega-invalid.log"
cp "$BASE" "$reject_image"
mcopy -o -i "$reject_image" "$ROOT/src/DEV/EGA/EGA.SYS" ::EGA.SYS
mcopy -o -i "$reject_image" "$PROBE" ::EGAPROBE.COM
mcopy -o -i "$reject_image" "$QEXIT" ::QEXIT.COM
printf 'DEVICE=EGA.SYS FUNC=7F\r\n' | mcopy -o -i "$reject_image" - ::CONFIG.SYS
printf '@ECHO OFF\r\nCTTY AUX\r\nEGAPROBE.COM\r\nIF ERRORLEVEL 1 ECHO EGA_INVALID_REJECTED\r\nQEXIT.COM\r\n' |
    mcopy -o -i "$reject_image" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$reject_image",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$reject_log" 2>&1 || true
grep -q 'EGA_FAIL_MUX' "$reject_log"
grep -q 'EGA_INVALID_REJECTED' "$reject_log"

echo "EGA.SYS API passed multiplex, BIOS-shadow, RIL access, and defaults contracts"
