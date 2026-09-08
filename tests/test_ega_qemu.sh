#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"

[[ -f "$BASE" ]] || { echo "missing $BASE; run make deploy" >&2; exit 1; }
mkdir -p "$OUT"
WORKDIR=$(mktemp -d "$OUT/ega-qemu.XXXXXX")
echo "EGA test artifacts: $WORKDIR"
PROBE="$WORKDIR/ega-api-probe.com"
QEXIT="$WORKDIR/ega-qexit.com"
nasm -f bin "$ROOT/tests/ega_api_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"

run_case() {
    local name="$1"
    local option="$2"
    local image="$WORKDIR/ega-$name.img"
    local log="$WORKDIR/ega-$name.log"

    # Test the supplied driver, including its absence in deletion audits.
    cp "$BASE" "$image"
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
    if ! grep -q 'EGA_API_OK' "$log" ||
        grep -Eq 'EGA_FAIL_|EGA_PROBE_FAILED' "$log"; then
        cat "$log" >&2
        return 1
    fi
}

run_case default ""
run_case custom "FUNC=AC"

reject_image="$WORKDIR/ega-invalid.img"
reject_log="$WORKDIR/ega-invalid.log"
cp "$BASE" "$reject_image"
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
