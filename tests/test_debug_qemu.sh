#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

BOOT_IMG="$OUT/debug-qemu-boot.img"
SERIAL_LOG="$OUT/debug-qemu-serial.log"
DEBUGCON_LOG="$OUT/debug-qemu-debugcon.log"
EXIT_COM="$OUT/debug-qemu-exit.com"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== DEBUG G (execute) E2E test (QEMU) ==="

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"
printf 'DEVICE=A:\\EMM386.EXE M5\r\n' | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM

{
    printf 'o e9 41\r\n'
    printf 'i e9\r\n'
    printf 'a 120\r\n'
    printf 'mov ax,1234\r\n'
    printf 'nop\r\n'
    printf 'int 20\r\n'
    printf '\r\n'
    printf 'r ip\r\n'
    printf '120\r\n'
    printf 't\r\n'
    printf 'p\r\n'
    printf 'a 100\r\n'
    printf 'mov ah,9\r\n'
    printf 'mov dx,110\r\n'
    printf 'int 21\r\n'
    printf 'int 20\r\n'
    printf '\r\n'
    printf 'e 110 48 45 4c 4c 4f 24\r\n'
    printf 'r ip\r\n'
    printf '100\r\n'
    printf 'g\r\n'
    printf 'x s\r\n'
    printf 'x a 1\r\n'
    printf 'x m 0 0 1\r\n'
    printf 'x d 1\r\n'
    printf 'q\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::DBGCMD.TXT

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'ECHO ---DEBUG-G---\r\n'
    printf 'DEBUG < DBGCMD.TXT\r\n'
    printf 'ECHO DEBUG_G_DONE\r\n'
    printf 'ECHO ===DONE===\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

echo "Booting QEMU (may take ~90s)..."
rm -f "$SERIAL_LOG" "$DEBUGCON_LOG"
(while true; do sleep 0.5; printf '\r\n'; done) | \
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    -debugcon "file:$DEBUGCON_LOG" -global isa-debugcon.iobase=0xe9 \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

echo ""
echo "--- DEBUG G tests ---"

if [[ "$(cat "$DEBUGCON_LOG" 2>/dev/null)" == "A" ]]; then
    ok "DEBUG O: wrote the exact byte 41h to I/O port E9h"
else
    fail "DEBUG O: expected exact debug-console byte 'A'"
fi

if grep -Eq '^E9' "$SERIAL_LOG"; then
    ok "DEBUG I: read and displayed one byte from I/O port E9h"
else
    fail "DEBUG I: expected a two-digit port-input result"
fi

if grep -q 'AX=1234' "$SERIAL_LOG"; then
    ok "DEBUG T: single-step executed MOV AX,1234"
else
    fail "DEBUG T: expected AX=1234 after single-step"
fi

if grep -Eq 'IP=0124' "$SERIAL_LOG"; then
    ok "DEBUG P: proceeded over NOP to IP 0124"
else
    fail "DEBUG P: expected IP=0124 after proceed"
fi

if grep -qi 'EMS pages' "$SERIAL_LOG" && grep -qi 'EMS handles' "$SERIAL_LOG"; then
    ok "DEBUG X S: reported live EMS page and handle status"
else
    fail "DEBUG X S: expected EMS status report"
fi

if grep -qi 'Handle Created' "$SERIAL_LOG" \
    && grep -qi 'mapped to physical page' "$SERIAL_LOG" \
    && grep -qi 'deallocated' "$SERIAL_LOG"; then
    ok "DEBUG X A/M/D: allocated, mapped, and released an EMS handle"
else
    fail "DEBUG X A/M/D: expected the complete EMS handle lifecycle"
fi

if grep -q "HELLO" "$SERIAL_LOG"; then
    ok "DEBUG G: program output 'HELLO' appeared on serial (INT 21h/9 via COM1)"
else
    fail "DEBUG G: expected 'HELLO' from assembled program (INT 21h/AH=9)"
fi

if grep -qi "Program terminated normally" "$SERIAL_LOG"; then
    ok "DEBUG G: 'Program terminated normally' (INT 20h caught by DEBUG's INT 22h handler)"
else
    fail "DEBUG G: expected 'Program terminated normally' message from DEBUG"
fi

if grep -q "DEBUG_G_DONE" "$SERIAL_LOG"; then
    ok "DEBUG G: batch continued after DEBUG exited"
else
    fail "DEBUG G: batch hung or crashed after DEBUG"
fi

if grep -q "===DONE===" "$SERIAL_LOG"; then
    ok "Batch reached ===DONE==="
else
    fail "Batch did NOT reach ===DONE=== (hung or crashed early)"
    echo "--- last 20 lines of serial log ---"
    tail -20 "$SERIAL_LOG"
    echo "---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
