#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/floppy-emm386-qemu.img"
PROBE_COM="$OUT/emm386-probe.com"
SERIAL_LOG="$OUT/emm386-qemu.log"

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
nasm -f bin "$REPO_ROOT/tests/emm386_probe.asm" -o "$PROBE_COM"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::EMMPROBE.COM
printf 'DEVICE=A:\\EMM386.SYS M5\r\n' \
    | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'EMMPROBE.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

timeout 35 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$SERIAL_LOG" 2>&1 || true

if grep -q 'EMM386_API_PASS' "$SERIAL_LOG"; then
    echo "  PASS: EMM386 entered protected mode and passed EMS allocation, mapping, alias, and release checks"
    exit 0
fi

echo "  FAIL: EMM386 functional probe did not complete"
sed -n '1,160p' "$SERIAL_LOG"
exit 1
