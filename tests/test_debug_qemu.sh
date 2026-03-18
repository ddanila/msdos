#!/bin/bash
# tests/test_debug_qemu.sh — E2E test for DEBUG's G (go/execute) command via QEMU.
#
# DEBUG.COM (DEBCOM3.ASM) — the G command:
#   1. Sets optional breakpoints by writing INT 3 (0xCCh) at target addresses.
#   2. Calls DEXIT, which uses INT 21h/AH=5Dh/AL=0Ah (save extended error state)
#      — unsupported in kvikdos, so G cannot run there.
#   3. IRETs to CS:IP (the user program).
#   4. Re-enters DEBUG via INT 1 (single-step trap) on breakpoint, or INT 22h
#      (terminate address) when the program exits via INT 20h / INT 21h/4Ch.
#   5. Prints "Program terminated normally" (message 9) and returns to prompt.
#
# Test approach — assemble and run a minimal COM-style program inside DEBUG:
#
#   a 100               assemble at CS:0100 (COM entry point)
#   mov ah,9            AH=9 → INT 21h print string
#   mov dx,110          DX → offset of message (CS:0110)
#   int 21              print "HELLO$" to stdout (handle 1 = COM1 via CTTY AUX)
#   int 20              terminate → DOS calls INT 22h → DEBUG REENTER
#                       (blank line ends assembly)
#   e 110 48 45 4c 4c 4f 24   enter bytes: H E L L O $
#   g                   execute from CS:IP (CS:0100) — runs our program
#   q                   quit DEBUG after "Program terminated normally"
#
# With CTTY AUX, DOS handle 1 (stdout) is COM1.  INT 21h/AH=9 prints through
# the handle, so "HELLO" appears on the serial log alongside DEBUG's own output.
#
# Run via: make test-debug-qemu  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/debug-qemu-boot.img"
SERIAL_LOG="$OUT/debug-qemu-serial.log"

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

# ── Build test floppy ─────────────────────────────────────────────────────────
echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"

# DBGCMD.TXT — DEBUG command script (DOS line endings).
#
# Program assembled at CS:0100 (COM-style entry point):
#   0100: B4 09    mov ah,9        ; INT 21h print-string function
#   0102: BA 10 01 mov dx,0110     ; DS:DX → "HELLO$" at offset 0x110
#   0105: CD 21    int 21          ; print string to stdout (COM1 via CTTY AUX)
#   0107: CD 20    int 20          ; terminate → DOS → INT 22h → DEBUG REENTER
#
# String "HELLO$" at offset 0x110 (hex: 48 45 4C 4C 4F 24).
{
    printf 'a 100\r\n'
    printf 'mov ah,9\r\n'
    printf 'mov dx,110\r\n'
    printf 'int 21\r\n'
    printf 'int 20\r\n'
    printf '\r\n'
    printf 'e 110 48 45 4c 4c 4f 24\r\n'
    printf 'g\r\n'
    printf 'q\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::DBGCMD.TXT

# AUTOEXEC.BAT: run DEBUG with command script redirected from DBGCMD.TXT.
# Input redirection (<) overrides CTTY AUX for DEBUG's stdin only;
# DEBUG's stdout (prompts, disassembly) and the program's output still go
# to COM1 (handle 1 = AUX via CTTY AUX).
{
    printf 'CTTY AUX\r\n'
    printf 'ECHO ---DEBUG-G---\r\n'
    printf 'DEBUG < DBGCMD.TXT\r\n'
    printf 'ECHO DEBUG_G_DONE\r\n'
    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Boot QEMU and capture serial output ──────────────────────────────────────
echo "Booting QEMU (may take ~90s)..."
rm -f "$SERIAL_LOG"
(while true; do sleep 0.5; printf '\r\n'; done) | \
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

# ── Checks ────────────────────────────────────────────────────────────────────
echo ""
echo "--- DEBUG G tests ---"

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
