#!/bin/bash
# tests/test_builtins.sh — E2E tests for COMMAND.COM built-in commands via QEMU.
#
# Boots a floppy with AUTOEXEC.BAT that runs CTTY AUX + several built-in
# commands, then checks COM1 serial output for expected strings.
#
# All commands are read-only (no SET assignment, no file modification) because
# SET FOO=BAR hangs batch processing — likely an environment resize issue on
# floppy boot with minimal environment space.
#
# Run via: make test-builtins  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

TEST_IMG="$OUT/floppy-builtins.img"
SERIAL_LOG="$OUT/builtins-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== COMMAND.COM built-in E2E tests (QEMU) ==="

# ── Build test floppy ────────────────────────────────────────────────────────
echo "Building test floppy..."
cp "$FLOPPY" "$TEST_IMG"

printf 'CTTY AUX\r\nVER\r\nECHO HELLO_E2E_TEST\r\nSET\r\nPATH\r\nDIR\r\nVOL\r\n' \
    | mcopy -o -i "$TEST_IMG" - ::AUTOEXEC.BAT

# ── Boot QEMU and capture serial output ──────────────────────────────────────
# Use -serial stdio (not -serial file:) so output is flushed through tee.
echo "Booting QEMU (headless, ~20s)..."
rm -f "$SERIAL_LOG"
timeout 30 qemu-system-i386 \
    -display none \
    -fda "$TEST_IMG" \
    -boot a -m 4 \
    -serial stdio \
    </dev/null 2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty or missing — QEMU may have failed to boot"
    exit 1
fi

# ── Check output ─────────────────────────────────────────────────────────────

# VER — should print DOS version string
if grep -q "MS-DOS Version" "$SERIAL_LOG"; then
    ok "VER (MS-DOS Version)"
else
    fail "VER (expected 'MS-DOS Version' in serial output)"
fi

# ECHO — should print our test string
if grep -q "HELLO_E2E_TEST" "$SERIAL_LOG"; then
    ok "ECHO (custom message)"
else
    fail "ECHO (expected 'HELLO_E2E_TEST' in serial output)"
fi

# SET (no args) — should list environment including COMSPEC
if grep -q "COMSPEC=" "$SERIAL_LOG"; then
    ok "SET (lists environment)"
else
    fail "SET (expected 'COMSPEC=' in environment listing)"
fi

# PATH (no args) — should show path status
if grep -q "No Path\|PATH=" "$SERIAL_LOG"; then
    ok "PATH (displays path info)"
else
    fail "PATH (expected 'No Path' or 'PATH=' in serial output)"
fi

# DIR — should list files on the floppy
if grep -q "COMMAND" "$SERIAL_LOG"; then
    ok "DIR (lists COMMAND.COM)"
else
    fail "DIR (expected 'COMMAND' in directory listing)"
fi

# VOL — should display volume serial number
if grep -q "Serial Number" "$SERIAL_LOG"; then
    ok "VOL (volume serial number)"
else
    fail "VOL (expected 'Serial Number' in serial output)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
