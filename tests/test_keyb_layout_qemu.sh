#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
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
    for code in BR PL CZ SL YU HU; do
        if [[ "$code" == BR ]]; then
            page=437
        else
            page=850
        fi
        printf 'KEYB %s,%s,KEYBOARD.SYS\r\n' "$code" "$page"
        printf 'IF ERRORLEVEL 1 ECHO %s_LAYOUT_FAILED\r\n' "$code"
        printf 'KEYB\r\n'
    done
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
for code in BR PL CZ SL YU HU; do
    if grep -qi "Current keyboard code: $code" "$SERIAL_LOG" &&
       ! grep -q "${code}_LAYOUT_FAILED" "$SERIAL_LOG"; then
        echo "  PASS: KEYB loaded and reported the $code DOS 5 layout"
        PASS=$((PASS+1))
    else
        echo "  FAIL: KEYB did not load/report the $code DOS 5 layout"
    fi
done
if grep -q "KEYB_LAYOUT_DONE" "$SERIAL_LOG"; then
    echo "  PASS: command interpreter resumed after KEYB"
    PASS=$((PASS+1))
else
    echo "  FAIL: command interpreter did not resume after KEYB"
fi

echo "Results: $PASS passed, $((8-PASS)) failed"
[[ $PASS -eq 8 ]]
