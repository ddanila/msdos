#!/bin/bash
# Focused KEYB parser/state regression test for non-US layouts.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/keyb-layout-test.img"
SERIAL_LOG="$OUT/keyb-layout-test.log"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

cp "$FLOPPY" "$BOOT_IMG"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'KEYB GR,,KEYBOARD.SYS\r\n'
    printf 'KEYB\r\n'
    printf 'ECHO KEYB_LAYOUT_DONE\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

(while true; do sleep 0.5; printf '\r\n'; done) | \
timeout 30 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

PASS=0
if grep -qi "Current keyboard code.*GR\|code.*GR" "$SERIAL_LOG"; then
    echo "  PASS: KEYB loaded and reported the German layout"
    PASS=$((PASS+1))
else
    echo "  FAIL: KEYB did not load/report the German layout"
fi
if grep -q "KEYB_LAYOUT_DONE" "$SERIAL_LOG"; then
    echo "  PASS: command interpreter resumed after KEYB"
    PASS=$((PASS+1))
else
    echo "  FAIL: command interpreter did not resume after KEYB"
fi

echo "Results: $PASS passed, $((2-PASS)) failed"
[[ $PASS -eq 2 ]]
