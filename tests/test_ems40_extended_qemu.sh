#!/bin/bash

set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="$OUT/floppy.img"
IMAGE="$OUT/floppy-ems40-extended.img"
PROBE="$OUT/ems40-extended.com"
LOG="$OUT/ems40-extended.log"

[[ -f "$BASE" ]] || { echo "ERROR: run 'make deploy' first"; exit 1; }
for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing $tool"; exit 1; }
done

nasm -f bin "$ROOT/tests/ems40_extended_probe.asm" -o "$PROBE"
cp "$BASE" "$IMAGE"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$IMAGE" "$PROBE" ::EMS40.COM
{
    printf '%s\r\n' 'DEVICE=A:\HIMEM.SYS /TESTMEM:OFF'
    printf '%s\r\n' 'DEVICE=A:\EMM386.EXE RAM'
} | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nCTTY AUX\r\nEMS40.COM\r\n' \
    | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true

if grep -q 'EMS40_EXTENDED_PASS' "$LOG"; then
    echo '  PASS: LIM EMS 4.0 extended lifecycle and OS/E contracts'
    exit 0
fi
echo '  FAIL: LIM EMS 4.0 extended probe did not complete'
sed -n '1,180p' "$LOG"
exit 1
