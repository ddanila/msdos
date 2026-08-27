#!/bin/bash
# Focused MODE parser and LPT1:=COM1: resident-install regression test.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/mode-redirect-test.img"
SERIAL_LOG="$OUT/mode-redirect-test.log"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

cp "$FLOPPY" "$BOOT_IMG"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'MODE COM1: BAUD=9600 PARITY=N DATA=8 STOP=1\r\n'
    printf 'MODE LPT1:=COM1:\r\n'
    printf 'ECHO MODE_REDIRECT_DONE\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

(while true; do sleep 0.5; printf '\r\n'; done) | \
timeout 30 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

PASS=0
if grep -qi "COM1: *9600,n,8,1" "$SERIAL_LOG"; then
    echo "  PASS: MODE parsed all COM1 keyword parameters"
    PASS=$((PASS+1))
else
    echo "  FAIL: MODE did not apply all COM1 keyword parameters"
fi
if grep -qi "rerouted to COM1\|LPT1.*rerouted" "$SERIAL_LOG"; then
    echo "  PASS: MODE reported LPT1 redirection"
    PASS=$((PASS+1))
else
    echo "  FAIL: MODE did not report LPT1 redirection"
fi
if grep -q "MODE_REDIRECT_DONE" "$SERIAL_LOG"; then
    echo "  PASS: command interpreter resumed after resident installation"
    PASS=$((PASS+1))
else
    echo "  FAIL: command interpreter did not resume after resident installation"
fi

echo "Results: $PASS passed, $((3-PASS)) failed"
[[ $PASS -eq 3 ]]
