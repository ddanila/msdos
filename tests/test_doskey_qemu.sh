#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/floppy-doskey.img"
LOG="$OUT/doskey.log"
PROBE="$OUT/DKPROBE.COM"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done
[[ -f "$BASE" ]] || { echo "ERROR: missing $BASE" >&2; exit 1; }

nasm -f bin "$ROOT/tests/doskey_probe.asm" -o "$PROBE"
cp "$BASE" "$IMAGE"
mcopy -o -i "$IMAGE" "$PROBE" ::DKPROBE.COM
printf 'hi one two\r\nmulti\r\necho RAW_HISTORY\r\n' | mcopy -o -i "$IMAGE" - ::DKINPUT.TXT
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'DOSKEY /BUFSIZE:1024\r\n'
    printf 'DOSKEY hi=echo MACRO_OK $1 $*\r\n'
    printf 'DOSKEY multi=echo MULTI_ONE$Techo MULTI_TWO\r\n'
    printf 'DOSKEY /INSERT\r\n'
    printf 'DOSKEY /MACROS\r\n'
    printf 'DKPROBE.COM < DKINPUT.TXT\r\n'
    printf 'DOSKEY /HISTORY\r\n'
    printf 'DOSKEY /OVERSTRIKE\r\n'
    printf 'DOSKEY /REINSTALL\r\n'
    printf 'ECHO DOSKEY_TEST_END\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 30 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot >"$LOG" 2>&1 || true

for marker in \
    'DOSKEY installed.' \
    'HI=echo MACRO_OK $1 $*' \
    'MULTI=echo MULTI_ONE$Techo MULTI_TWO' \
    'DOSKEY_4800_PASS' \
    'DOSKEY_FIRST=[echo MACRO_OK one one two]' \
    'DOSKEY_SECOND=[echo MULTI_ONE]' \
    'DOSKEY_THIRD=[echo MULTI_TWO]' \
    'DOSKEY_FOURTH=[echo RAW_HISTORY]' \
    'DOSKEY_UP=[echo RAW_HISTORY]' \
    'DOSKEY_PGUP=[echo MACRO_OK one one two]' \
    'DOSKEY_DOWN=[echo MULTI_ONE]' \
    'DOSKEY_PGDN=[echo MULTI_ONE]' \
    'DOSKEY_F8=[echo MULTI_ONE]' \
    'DOSKEY_F8_PENDING=[echo MULTI_TWO]' \
    '1: hi one two' \
    '2: multi' \
    'DOSKEY_F7_RETURN=[]' \
    'DOSKEY_F9=[echo MULTI_ONE]' \
    'DOSKEY_ALTF7_UP=[]' \
    'DOSKEY_PROBE_PASS' \
    'hi one two' \
    'multi' \
    'echo RAW_HISTORY' \
    'DOSKEY reinstalled; history and macros cleared.' \
    'DOSKEY_TEST_END'; do
    grep -Fq "$marker" "$LOG" || {
        echo "FAIL: DOSKEY contract missing: $marker" >&2
        sed -n '1,220p' "$LOG" >&2
        exit 1
    }
done

echo '  PASS: DOSKEY APIs, macros, redirected input, navigation keys, modes, sizing, and reinstall'
