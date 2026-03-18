#!/bin/bash
# tests/test_help_qemu.sh — Verify EXEPACK integrity for all external CMD tools on real DOS.
#
# Boots a floppy with AUTOEXEC.BAT that runs every external CMD tool with /?
# and captures COM1 serial output.  The sole purpose is to confirm that no tool
# prints "Packed file is corrupt", which would indicate a broken EXEPACK header.
#
# /? functional output is already checked under kvikdos in run_tests.sh Section 4.
#
# Run via: make test-help-qemu  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

TEST_IMG="$OUT/floppy-help-qemu.img"
SERIAL_LOG="$OUT/help-qemu-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== EXEPACK integrity test (QEMU) ==="

# ── Build test floppy ────────────────────────────────────────────────────────
# Run all tools with /? in one boot to exercise the EXEPACK decompressor for
# every packed binary.  Skipped tools (TSRs / interactive / stdin filters):
#   NLSFUNC, SHARE, APPEND, PRINT, GRAPHICS, FASTOPEN, DEBUG, EDLIN, MORE, SORT

echo "Building test floppy..."
cp "$FLOPPY" "$TEST_IMG"

{
    printf 'CTTY AUX\r\n'
    printf 'MEM /?\r\n'
    printf 'ATTRIB /?\r\n'
    printf 'XCOPY /?\r\n'
    printf 'FORMAT /?\r\n'
    printf 'FC /?\r\n'
    printf 'JOIN /?\r\n'
    printf 'SUBST /?\r\n'
    printf 'REPLACE /?\r\n'
    printf 'FIND /?\r\n'
    printf 'TREE /?\r\n'
    printf 'BACKUP /?\r\n'
    printf 'RESTORE /?\r\n'
    printf 'DISKCOMP /?\r\n'
    printf 'DISKCOPY /?\r\n'
    printf 'GRAFTABL /?\r\n'
    printf 'LABEL /?\r\n'
    printf 'COMP /?\r\n'
    printf 'ASSIGN /?\r\n'
    printf 'SYS /?\r\n'
    printf 'EXE2BIN /?\r\n'
    printf 'KEYB /?\r\n'
    printf 'MODE /?\r\n'
    printf 'RECOVER /?\r\n'
    printf 'CHKDSK /?\r\n'
    printf 'FILESYS /?\r\n'
    printf 'FDISK /?\r\n'
    printf 'IFSFUNC /?\r\n'
    printf 'ECHO ---DONE---\r\n'
} | mcopy -o -i "$TEST_IMG" - ::AUTOEXEC.BAT

# ── Boot QEMU and capture serial output ──────────────────────────────────────
echo "Booting QEMU (headless, ~40s)..."
rm -f "$SERIAL_LOG"
timeout 50 qemu-system-i386 \
    -display none \
    -fda "$TEST_IMG" \
    -boot a -m 4 \
    -serial stdio \
    </dev/null 2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty or missing — QEMU may have failed to boot"
    exit 1
fi

# ── EXEPACK integrity check ───────────────────────────────────────────────────
if grep -qi "Packed file is corrupt" "$SERIAL_LOG"; then
    fail "EXEPACK corruption detected in one or more tools"
else
    ok "EXEPACK: no corruption in any tool"
fi

if grep -q "DONE" "$SERIAL_LOG"; then
    ok "QEMU boot ran to completion"
else
    fail "QEMU boot did not reach ---DONE--- marker (crash or hang?)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Serial log saved to: $SERIAL_LOG"
fi
[[ $FAIL -eq 0 ]]
