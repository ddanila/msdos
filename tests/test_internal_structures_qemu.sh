#!/bin/bash

set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="$OUT/floppy.img"
IMAGE="$OUT/floppy-internal-structures.img"
PROBE="$OUT/internal-structures.com"
LOG="$OUT/internal-structures.log"

if [[ ! -f "$BASE" ]]; then
    echo "ERROR: $BASE not found — run 'make deploy' first"
    exit 1
fi

for tool in nasm mcopy qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

nasm -f bin "$ROOT/tests/internal_structures_probe.asm" -o "$PROBE"
cp "$BASE" "$IMAGE"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$IMAGE" "$PROBE" ::INTERNAL.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'INTERNAL.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

rm -f "$LOG"
timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$LOG" 2>&1 || true

if grep -q 'INTERNAL_STRUCTURES_PASS' "$LOG"; then
    echo "  PASS: observable PSP, MCB, LoL, DPB, CDS, SFT, SDA, and device-chain layouts"
    exit 0
fi

echo "  FAIL: internal-structure probe did not complete"
sed -n '1,180p' "$LOG"
exit 1
