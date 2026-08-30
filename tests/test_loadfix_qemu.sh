#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
IMAGE="$OUT/floppy-loadfix.img"
LOG="$OUT/loadfix.log"
PROBE="$OUT/LFPROBE.COM"

cp "$OUT/floppy.img" "$IMAGE"
nasm -f bin "$ROOT/tests/loadfix_probe.asm" -o "$PROBE"
mcopy -o -i "$IMAGE" "$ROOT/src/CMD/LOADFIX/LOADFIX.COM" ::LOADFIX.COM
mcopy -o -i "$IMAGE" "$PROBE" ::LFPROBE.COM
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'LOADFIX LFPROBE.COM ARG1 ARG2\r\n'
    printf 'IF ERRORLEVEL 38 ECHO LOADFIX_STATUS_FAIL\r\n'
    printf 'IF ERRORLEVEL 37 ECHO LOADFIX_STATUS_PASS\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$OUT/qemu-exit.com"
mcopy -o -i "$IMAGE" "$OUT/qemu-exit.com" ::QEXIT.COM

timeout 20 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true

grep -Fq 'LOADFIX_HIGH ARG1 ARG2' "$LOG"
grep -Fq 'LOADFIX_STATUS_PASS' "$LOG"
! grep -Fq 'LOADFIX_STATUS_FAIL' "$LOG"
echo '  PASS: LOADFIX placement, argument forwarding, and child status propagation'
