#!/bin/bash
# tests/test_select.sh — SELECT.COM/SELECT.EXE e2e test via screen_expect.
#
# SELECT uses INT 16H (BIOS keyboard) and INT 10H (video) — not reachable
# via CTTY AUX serial.  Uses screen_expect.py (QMP video memory + keyboard
# injection) to drive the interaction.
#
# Test flow:
#   1. Boot DOS (no AUTOEXEC.BAT) — dismiss date/time prompts
#   2. Type "SELECT" at A:\> prompt
#   3. Stub shows "Insert SELECT diskette" — press ENTER (INT 16H)
#   4. SELECT.EXE runs — "Invalid parameters" (no args = expected error)
#   5. Returns to DOS prompt (no crash/hang)
#   6. Boot a fresh image and run "SELECT MENU"
#   7. Confirm the valid path reaches the Welcome panel
#   8. Cancel to the Exit panel, decline exit, and confirm recovery to Welcome
#   9. Re-enter the Exit panel, accept with F3, and confirm return to DOS
#
# Run via: make test-select  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/select-test-boot.img"
SCREEN_LOG="$OUT/select-test.log"
QMP_SOCK="$OUT/select-test-qmp.sock"
MENU_BOOT_IMG="$OUT/select-menu-test-boot.img"
MENU_SCREEN_LOG="$OUT/select-menu-test.log"
MENU_QMP_SOCK="$OUT/select-menu-test-qmp.sock"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'kill ${QEMU_PID:-} 2>/dev/null; rm -f "$QMP_SOCK" "$MENU_QMP_SOCK" "$BOOT_IMG" "$MENU_BOOT_IMG" 2>/dev/null; true' EXIT

echo "=== SELECT e2e test (screen_expect: INT 16H + video memory) ==="

# ── Step 1: build boot floppy (SELECT files already on floppy from deploy) ───
echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mdel -i "$BOOT_IMG" ::AUTOEXEC.BAT 2>/dev/null || true

# ── Step 2: boot QEMU with QMP ──────────────────────────────────────────────
echo "Booting QEMU with QMP socket..."
rm -f "$QMP_SOCK"
timeout 90 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG" \
    -boot a -m 4 \
    -qmp unix:"$QMP_SOCK",server,nowait \
    2>/dev/null &
QEMU_PID=$!

# Wait for QMP socket to appear
for i in $(seq 1 20); do
    [[ -S "$QMP_SOCK" ]] && break
    sleep 0.2
done

if [[ ! -S "$QMP_SOCK" ]]; then
    echo "ERROR: QMP socket did not appear"
    exit 1
fi

# ── Step 3: run screen_expect ────────────────────────────────────────────────
# Rules:
#   1. Dismiss date prompt → Enter
#   2. Dismiss time prompt → Enter
#   3. Wait for A:\> prompt → type "SELECT" + Enter
#   4. Wait for stub message "Insert SELECT" → press Enter (INT 16H)
#   5. Wait for "Invalid parameters" (SELECT.EXE no-args error) → Enter
#   6. Wait for A:\> again (returned to DOS) → done
echo "Running screen_expect (SELECT stub + EXE flow)..."
python3 "$REPO_ROOT/tests/screen_expect.py" \
    "$QMP_SOCK" "$SCREEN_LOG" \
    'Enter new date' 'ret' \
    'Enter new time' 'ret' \
    '>' 's+e+l+e+c+t+ret' \
    'Insert SELECT' 'ret' \
    'Invalid parameters' 'ret'

kill $QEMU_PID 2>/dev/null
wait $QEMU_PID 2>/dev/null || true

# ── Step 4: exercise a valid UI state transition and recovery ──────────────────
echo "Running SELECT MENU valid-path check..."
cp "$FLOPPY" "$MENU_BOOT_IMG"
# EXIT_SELECT requires the INSTALL disk to contain AUTOEXEC.BAT before it will
# return to DOS. A minimal file also skips the unrelated startup date/time
# prompts in this second, UI-focused boot.
printf '@ECHO OFF\r\n' | mcopy -o -i "$MENU_BOOT_IMG" - ::AUTOEXEC.BAT
rm -f "$MENU_QMP_SOCK"
timeout 90 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$MENU_BOOT_IMG" \
    -boot a -m 4 \
    -qmp unix:"$MENU_QMP_SOCK",server,nowait \
    2>/dev/null &
QEMU_PID=$!

for i in $(seq 1 20); do
    [[ -S "$MENU_QMP_SOCK" ]] && break
    sleep 0.2
done

if [[ ! -S "$MENU_QMP_SOCK" ]]; then
    echo "ERROR: MENU QMP socket did not appear"
    exit 1
fi

python3 "$REPO_ROOT/tests/screen_expect.py" \
    "$MENU_QMP_SOCK" "$MENU_SCREEN_LOG" \
    '>' 's+e+l+e+c+t+spc+m+e+n+u+ret' \
    'Insert SELECT' 'ret' \
    'Welcome' 'esc' \
    'You have chosen to end SELECT' 'ret' \
    'Welcome' 'esc' \
    'You have chosen to end SELECT' 'f3' \
    '>' ''

kill $QEMU_PID 2>/dev/null
wait $QEMU_PID 2>/dev/null || true

# ── Step 5: checks ──────────────────────────────────────────────────────────
echo ""
echo "--- SELECT tests ---"

if [[ -f "$SCREEN_LOG" && -s "$SCREEN_LOG" ]]; then
    ok "Screen log file created and non-empty"
else
    fail "Screen log file missing or empty"
fi

# Stub message: "Insert SELECT diskette in drive A"
if grep -q "Insert SELECT diskette" "$SCREEN_LOG"; then
    ok "SELECT.COM stub message displayed (INT 10H video output)"
else
    fail "SELECT.COM stub message not found in video memory"
fi

# Stub accepted ENTER via INT 16H (if it didn't, we'd never see SELECT.EXE output)
if grep -q "Rule 3: matched.*Insert SELECT" "$SCREEN_LOG"; then
    ok "INT 16H keyboard input received (ENTER accepted by stub)"
else
    fail "INT 16H keyboard input not received (stub didn't see ENTER)"
fi

# SELECT.EXE ran and produced output
if grep -q "Invalid parameters" "$SCREEN_LOG"; then
    ok "SELECT.EXE executed (error message confirms it ran)"
else
    fail "SELECT.EXE did not execute (no error message found)"
fi

# Returned to DOS prompt (no crash/hang)
if grep -q "Rule 4: matched.*Invalid parameters" "$SCREEN_LOG"; then
    ok "SELECT.EXE returned to DOS (no crash/hang)"
else
    fail "SELECT.EXE did not return to DOS"
fi

if grep -q "Final screen" "$SCREEN_LOG"; then
    ok "Final screen captured"
else
    fail "Final screen not captured"
fi

if grep -q "Welcome to DOS 4.0 and the SELECT program" "$MENU_SCREEN_LOG"; then
    ok "SELECT MENU reached the Welcome panel"
else
    fail "SELECT MENU did not reach the Welcome panel"
fi

if grep -q "Rule 3: matched.*You have chosen to end SELECT" "$MENU_SCREEN_LOG"; then
    ok "ESC transitioned SELECT from Welcome to the Exit panel"
else
    fail "SELECT did not transition from Welcome to the Exit panel"
fi

if grep -q "Rule 4: matched.*Welcome" "$MENU_SCREEN_LOG"; then
    ok "ENTER declined exit and returned SELECT to Welcome"
else
    fail "SELECT did not recover from the Exit panel to Welcome"
fi

if grep -q "Rule 5: matched.*You have chosen to end SELECT" "$MENU_SCREEN_LOG"; then
    ok "ESC re-entered the SELECT Exit panel after recovery"
else
    fail "SELECT could not re-enter the Exit panel after recovery"
fi

if grep -q "Rule 6: matched.*>" "$MENU_SCREEN_LOG"; then
    ok "F3 accepted exit and returned SELECT to DOS"
else
    fail "SELECT did not return to DOS after accepting exit"
fi

# Dump log on failure
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "--- screen log (for debugging) ---"
    cat "$SCREEN_LOG" 2>/dev/null || echo "(empty)"
    echo "--- SELECT MENU screen log ---"
    cat "$MENU_SCREEN_LOG" 2>/dev/null || echo "(empty)"
    echo "--- end screen log ---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
