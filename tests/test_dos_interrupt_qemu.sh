#!/bin/bash
# Assert synchronous DOS interrupt contracts on a clean boot.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/floppy-dos-interrupt.img"
PROBE_COM="$OUT/dosint.com"
SERIAL_LOG="$OUT/dos-interrupt.log"

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
nasm -f bin "$REPO_ROOT/tests/dos_interrupt_probe.asm" -o "$PROBE_COM"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::DOSINT.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'DOSINT.COM\r\n'
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

if grep -q 'DOS_INTERRUPT_PASS' "$SERIAL_LOG"; then
    echo "  PASS: DOS INT 29h fast-console and INT 2Fh default multiplex contracts"
    exit 0
fi

echo "  FAIL: DOS synchronous interrupt probe did not complete"
sed -n '1,180p' "$SERIAL_LOG"
exit 1
