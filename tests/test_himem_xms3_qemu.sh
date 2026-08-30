#!/bin/bash

set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/floppy-himem-xms3.img"
PROBE="$OUT/himem-xms3.com"
LOG="$OUT/himem-xms3.log"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing $tool"; exit 1; }
done
[[ -f "$BASE" ]] || { echo "ERROR: run make deploy first"; exit 1; }

nasm -f bin "$ROOT/tests/himem_xms3_probe.asm" -o "$PROBE"
cp "$BASE" "$IMAGE"
mcopy -o -i "$IMAGE" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
mcopy -o -i "$IMAGE" "$PROBE" ::XMS3.COM
printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\n' | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nCTTY AUX\r\nXMS3.COM\r\n' | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 25 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true

grep -Fq HIMEM_XMS3_PASS "$LOG"
! grep -Fq HIMEM_XMS3_FAIL "$LOG"
echo '  PASS: HIMEM XMS 3.0 identity and 32-bit memory APIs'
