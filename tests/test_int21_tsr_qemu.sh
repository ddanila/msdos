#!/bin/bash
# Assert terminate-and-stay-resident retention with a callable interrupt hook.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/floppy-int21-tsr.img"
TSR_COM="$OUT/i21tsr.com"
TRIGGER_COM="$OUT/i21trig.com"
SERIAL_LOG="$OUT/int21-tsr.log"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in nasm mcopy qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/int21_tsr_probe.asm" -o "$TSR_COM"
nasm -f bin "$REPO_ROOT/tests/int21_tsr_trigger.asm" -o "$TRIGGER_COM"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$TSR_COM" ::I21TSR.COM
mcopy -o -i "$BOOT_IMG" "$TRIGGER_COM" ::I21TRIG.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'I21TSR.COM\r\n'
    printf 'I21TRIG.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_LOG"
timeout 35 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$SERIAL_LOG" 2>&1 || true

if grep -q 'INT21_TSR_HANDLER_PASS' "$SERIAL_LOG" && \
   grep -q 'INT21_TSR_TRIGGER_PASS' "$SERIAL_LOG"; then
    echo "  PASS: INT 21h TSR retained memory and callable interrupt handler"
    exit 0
fi

echo "  FAIL: INT 21h TSR contract probe did not complete"
sed -n '1,180p' "$SERIAL_LOG"
exit 1
