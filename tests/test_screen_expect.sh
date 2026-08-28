#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/screen-test-boot.img"
SCREEN_LOG="$OUT/screen-test.log"
QMP_SOCK="$OUT/screen-test-qmp.sock"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'rm -f "$QMP_SOCK" 2>/dev/null; true' EXIT

echo "=== screen_expect.py smoke test (QEMU + QMP video memory) ==="

echo "Building test image (no AUTOEXEC.BAT)..."
cp "$FLOPPY" "$BOOT_IMG"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mdel -i "$BOOT_IMG" ::AUTOEXEC.BAT 2>/dev/null || true

echo "Booting QEMU with QMP socket..."
rm -f "$QMP_SOCK"
timeout 60 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG" \
    -boot a -m 4 \
    -qmp unix:"$QMP_SOCK",server,nowait \
    2>/dev/null &
QEMU_PID=$!

for i in $(seq 1 20); do
    [[ -S "$QMP_SOCK" ]] && break
    sleep 0.2
done

if [[ ! -S "$QMP_SOCK" ]]; then
    echo "ERROR: QMP socket did not appear"
    kill $QEMU_PID 2>/dev/null
    exit 1
fi

echo "Running screen_expect (read video RAM, type VER)..."
python3 "$REPO_ROOT/tests/screen_expect.py" \
    "$QMP_SOCK" "$SCREEN_LOG" \
    'Enter new date' 'ret' \
    'Enter new time' 'ret' \
    '>' 'v+e+r+ret' \
    'MS-DOS' 'ret'

kill $QEMU_PID 2>/dev/null
wait $QEMU_PID 2>/dev/null || true

echo ""
echo "--- screen_expect framework tests ---"

if [[ -f "$SCREEN_LOG" && -s "$SCREEN_LOG" ]]; then
    ok "Screen log file created and non-empty"
else
    fail "Screen log file missing or empty"
fi

if grep -q "MS-DOS" "$SCREEN_LOG"; then
    ok "VER output ('MS-DOS') captured from video memory"
else
    fail "Expected 'MS-DOS' in screen log (VER command output)"
fi

if grep -q "Rule 0: matched" "$SCREEN_LOG"; then
    ok "Rule 0 matched (date prompt dismissed)"
else
    fail "Rule 0 did not match (date prompt not found in video memory)"
fi

if grep -q "Rule 2: matched" "$SCREEN_LOG"; then
    ok "Rule 2 matched (DOS prompt detected)"
else
    fail "Rule 2 did not match (DOS prompt not found in video memory)"
fi

if grep -q "Rule 3: matched" "$SCREEN_LOG"; then
    ok "Rule 3 matched (VER output detected after keystroke injection)"
else
    fail "Rule 3 did not match (VER output not found after typing)"
fi

if grep -q "Final screen" "$SCREEN_LOG"; then
    ok "Final screen captured"
else
    fail "Final screen not captured"
fi

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "--- screen log (for debugging) ---"
    cat "$SCREEN_LOG" 2>/dev/null || echo "(empty)"
    echo "--- end screen log ---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
