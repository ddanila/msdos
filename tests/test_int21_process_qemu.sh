#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/floppy-int21-process.img"
PROBE_COM="$OUT/i21proc.com"
CHILD_COM="$OUT/i21child.com"
INT20_CHILD_COM="$OUT/int20child.com"
SERIAL_LOG="$OUT/int21-process.log"

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
nasm -f bin "$REPO_ROOT/tests/int21_process_probe.asm" -o "$PROBE_COM"
nasm -f bin "$REPO_ROOT/tests/int21_child_probe.asm" -o "$CHILD_COM"
nasm -f bin "$REPO_ROOT/tests/int20_child_probe.asm" -o "$INT20_CHILD_COM"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::I21PROC.COM
mcopy -o -i "$BOOT_IMG" "$CHILD_COM" ::I21CHILD.COM
mcopy -o -i "$BOOT_IMG" "$INT20_CHILD_COM" ::INT20.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'I21PROC.COM\r\n'
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

if grep -q 'INT21_PROCESS_PASS' "$SERIAL_LOG"; then
    echo "  PASS: INT 21h EXEC success/error, wait, IOCTL, and NLS contracts"
    exit 0
fi

echo "  FAIL: INT 21h process contract probe did not complete"
sed -n '1,180p' "$SERIAL_LOG"
exit 1
