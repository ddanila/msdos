#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/floppy-deltree.img"
LOG="$OUT/deltree.log"

cp "$BASE" "$IMAGE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$OUT/qemu-exit.com"
mcopy -o -i "$IMAGE" "$ROOT/src/CMD/DELTREE/DELTREE.EXE" ::DELTREE.EXE
mcopy -o -i "$IMAGE" "$OUT/qemu-exit.com" ::QEXIT.COM
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'MD ONE\r\nMD ONE\\TWO\r\nECHO PAYLOAD>ONE\\TWO\\LOCKED.TXT\r\n'
    printf 'ATTRIB +R ONE\\TWO\\LOCKED.TXT\r\nATTRIB +H ONE\\TWO\\LOCKED.TXT\r\n'
    printf 'ATTRIB +S ONE\\TWO\\LOCKED.TXT\r\n'
    printf 'MD THREE\r\nECHO THREE>THREE\\FILE.TXT\r\nDELTREE /Y ONE THREE\r\n'
    printf 'IF EXIST ONE\\NUL ECHO DELTREE_RECURSE_FAIL\r\nIF EXIST THREE\\NUL ECHO DELTREE_MULTI_FAIL\r\n'
    printf 'MD KEEP\r\nECHO N>ANSWER.TXT\r\nDELTREE KEEP <ANSWER.TXT\r\n'
    printf 'IF EXIST KEEP\\NUL ECHO DELTREE_DECLINE_PASS\r\n'
    printf 'ECHO Y>ANSWER.TXT\r\nDELTREE KEEP <ANSWER.TXT\r\n'
    printf 'IF NOT EXIST KEEP\\NUL ECHO DELTREE_ACCEPT_PASS\r\n'
    printf 'MD WILD1\r\nMD WILD2\r\nDELTREE /Y WILD?\r\n'
    printf 'IF NOT EXIST WILD1\\NUL IF NOT EXIST WILD2\\NUL ECHO DELTREE_WILD_PASS\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 25 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true

grep -Fq 'DELTREE_DECLINE_PASS' "$LOG"
grep -Fq 'DELTREE_ACCEPT_PASS' "$LOG"
grep -Fq 'DELTREE_WILD_PASS' "$LOG"
! grep -Fq 'DELTREE_RECURSE_FAIL' "$LOG"
! grep -Fq 'DELTREE_MULTI_FAIL' "$LOG"
echo '  PASS: DELTREE recursion, attributes, prompts, multiple targets, and wildcards'
