#!/bin/bash
# tests/test_tools_qemu.sh — Functional E2E tests for external CMD tools via QEMU.
#
# Boots a floppy with AUTOEXEC.BAT that exercises external CMD tools with
# various options, then checks COM1 serial output for expected results.
#
# Run via: make test-tools-qemu  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

TEST_IMG="$OUT/floppy-tools.img"
SERIAL_LOG="$OUT/tools-qemu-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== External CMD tool functional tests (QEMU) ==="

# ── Build test floppy ────────────────────────────────────────────────────────
echo "Building test floppy..."
cp "$FLOPPY" "$TEST_IMG"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# Create a multi-line test file for FIND tests.
# Must end with ^Z for DOS text mode compatibility.
printf 'alpha one\r\n' > /tmp/findtest.txt
printf 'BETA TWO\r\n' >> /tmp/findtest.txt
printf 'alpha three\r\n' >> /tmp/findtest.txt
printf 'gamma four\r\n' >> /tmp/findtest.txt
printf 'ALPHA FIVE\r\n' >> /tmp/findtest.txt
printf '\x1a' >> /tmp/findtest.txt
mcopy -o -i "$TEST_IMG" /tmp/findtest.txt ::FIND.DAT
rm -f /tmp/findtest.txt

# Build AUTOEXEC.BAT
{
    printf 'CTTY AUX\r\n'

    # ── FIND: basic search ────────────────────────────────────────────────
    printf 'ECHO ---FIND-BASIC---\r\n'
    printf 'FIND "alpha" FIND.DAT\r\n'

    # ── FIND /C: count matching lines ─────────────────────────────────────
    printf 'ECHO ---FIND-COUNT---\r\n'
    printf 'FIND /C "alpha" FIND.DAT\r\n'

    # ── FIND /N: line numbers ─────────────────────────────────────────────
    printf 'ECHO ---FIND-LINENUM---\r\n'
    printf 'FIND /N "gamma" FIND.DAT\r\n'

    # ── FIND /V: non-matching lines ───────────────────────────────────────
    printf 'ECHO ---FIND-INVERSE---\r\n'
    printf 'FIND /V "alpha" FIND.DAT\r\n'

    # ── FIND: no match (exit code) ────────────────────────────────────────
    printf 'ECHO ---FIND-NOMATCH---\r\n'
    printf 'FIND "zzzzz" FIND.DAT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FIND_NOMATCH_ERRORLEVEL\r\n'

    # ── FIND /I: case-insensitive (DOS 4.0 may not support /I) ───────────
    # Not tested — /I was added in later DOS versions.

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$TEST_IMG" - ::AUTOEXEC.BAT

# ── Boot QEMU and capture serial output ──────────────────────────────────────
echo "Booting QEMU (headless, ~30s)..."
rm -f "$SERIAL_LOG"
timeout 45 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$TEST_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    </dev/null 2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty or missing — QEMU may have failed to boot"
    exit 1
fi

# ── Check output ─────────────────────────────────────────────────────────────

echo ""
echo "--- FIND ---"

# Basic search: should find "alpha one" and "alpha three" (case-sensitive)
if grep -q "alpha one" "$SERIAL_LOG" && grep -q "alpha three" "$SERIAL_LOG"; then
    ok "FIND basic (found 'alpha' lines)"
else
    fail "FIND basic (expected 'alpha one' and 'alpha three')"
fi

# Basic search should NOT match uppercase ALPHA (case-sensitive)
# Extract FIND output between markers to avoid matching the ECHO command itself
if sed -n '/---FIND-BASIC---/,/---FIND-COUNT---/p' "$SERIAL_LOG" | grep -q "ALPHA FIVE"; then
    fail "FIND basic (matched 'ALPHA FIVE' — should be case-sensitive)"
else
    ok "FIND basic (case-sensitive, skipped 'ALPHA FIVE')"
fi

# /C count: should show count of 2 (two lowercase "alpha" lines)
if grep -q ": 2" "$SERIAL_LOG" || grep -q ":2" "$SERIAL_LOG"; then
    ok "FIND /C (count = 2)"
else
    fail "FIND /C (expected count of 2)"
fi

# /N line numbers: should show [4] for "gamma four" (line 4)
if grep -q "\[4\]" "$SERIAL_LOG"; then
    ok "FIND /N (line number [4] for 'gamma')"
else
    fail "FIND /N (expected '[4]' line number)"
fi

# /V inverse: should show lines NOT containing "alpha" — BETA, gamma, ALPHA
if grep -q "BETA TWO" "$SERIAL_LOG" && grep -q "gamma four" "$SERIAL_LOG"; then
    ok "FIND /V (shows non-matching lines)"
else
    fail "FIND /V (expected 'BETA TWO' and 'gamma four')"
fi

# No match: FIND should set errorlevel >= 1
if grep -q "FIND_NOMATCH_ERRORLEVEL" "$SERIAL_LOG"; then
    ok "FIND no-match errorlevel"
else
    fail "FIND no-match (expected errorlevel >= 1)"
fi

# Completion
echo ""
if grep -q "===DONE===" "$SERIAL_LOG"; then
    ok "AUTOEXEC.BAT ran to completion"
else
    fail "AUTOEXEC.BAT did not reach ===DONE==="
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Serial log saved to: $SERIAL_LOG"
fi
[[ $FAIL -eq 0 ]]
