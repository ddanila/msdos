#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/select-test-boot.img"
SCREEN_LOG="$OUT/select-test.log"
QMP_SOCK="$OUT/select-test-qmp.sock"
MENU_BOOT_IMG="$OUT/select-menu-test-boot.img"
MENU_SCREEN_LOG="$OUT/select-menu-test.log"
MENU_QMP_SOCK="$OUT/select-menu-test-qmp.sock"
FDISK_BOOT_IMG="$OUT/select-fdisk-test-boot.img"
FDISK_SCREEN_LOG="$OUT/select-fdisk-test.log"
FDISK_QMP_SOCK="$OUT/select-fdisk-test-qmp.sock"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'kill ${QEMU_PID:-} 2>/dev/null; rm -f "$QMP_SOCK" "$MENU_QMP_SOCK" "$FDISK_QMP_SOCK" "$BOOT_IMG" "$MENU_BOOT_IMG" "$FDISK_BOOT_IMG" 2>/dev/null; true' EXIT

echo "=== SELECT e2e test (screen_expect: INT 16H + video memory) ==="

echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
printf '@ECHO OFF\r\n' | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

echo "Booting QEMU with QMP socket..."
rm -f "$QMP_SOCK"
timeout 90 qemu-system-i386 \
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
    exit 1
fi

echo "Running screen_expect (SELECT stub + parser/control-file flow)..."
python3 "$REPO_ROOT/tests/screen_expect.py" \
    "$QMP_SOCK" "$SCREEN_LOG" \
    '>' 's+e+l+e+c+t+ret' \
    'Insert SELECT' 'ret' \
    'Invalid parameters' 's+e+l+e+c+t+spc+b+o+g+u+s+ret' \
    'Insert SELECT' 'ret' \
    'Invalid parameters' 's+e+l+e+c+t+spc+m+e+n+u+spc+e+x+t+r+a+ret' \
    'Insert SELECT' 'ret' \
    'Invalid parameters' ''

kill $QEMU_PID 2>/dev/null
wait $QEMU_PID 2>/dev/null || true

echo "Running SELECT FDISK missing-control-file check..."
cp "$FLOPPY" "$FDISK_BOOT_IMG"
printf '@ECHO OFF\r\n' | mcopy -o -i "$FDISK_BOOT_IMG" - ::AUTOEXEC.BAT
rm -f "$FDISK_QMP_SOCK"
timeout 90 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$FDISK_BOOT_IMG" \
    -boot a -m 4 \
    -qmp unix:"$FDISK_QMP_SOCK",server,nowait \
    2>/dev/null &
QEMU_PID=$!

for i in $(seq 1 20); do
    [[ -S "$FDISK_QMP_SOCK" ]] && break
    sleep 0.2
done

if [[ ! -S "$FDISK_QMP_SOCK" ]]; then
    echo "ERROR: FDISK QMP socket did not appear"
    exit 1
fi

python3 "$REPO_ROOT/tests/screen_expect.py" \
    "$FDISK_QMP_SOCK" "$FDISK_SCREEN_LOG" \
    '>' 's+e+l+e+c+t+spc+f+d+i+s+k+ret' \
    'Insert SELECT' 'ret' \
    '>' 'e+c+h+o+spc+s+e+l+e+c+t+f+d+i+s+k+r+e+t+u+r+n+e+d+ret' \
    'selectfdiskreturned' ''

kill $QEMU_PID 2>/dev/null
wait $QEMU_PID 2>/dev/null || true

echo "Running SELECT MENU valid-path check..."
cp "$FLOPPY" "$MENU_BOOT_IMG"
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

echo ""
echo "--- SELECT tests ---"

if [[ -f "$SCREEN_LOG" && -s "$SCREEN_LOG" ]]; then
    ok "Screen log file created and non-empty"
else
    fail "Screen log file missing or empty"
fi

if grep -q "Insert SELECT diskette" "$SCREEN_LOG"; then
    ok "SELECT.COM stub message displayed (INT 10H video output)"
else
    fail "SELECT.COM stub message not found in video memory"
fi

if grep -q "Rule 1: matched.*Insert SELECT" "$SCREEN_LOG"; then
    ok "INT 16H keyboard input received (ENTER accepted by stub)"
else
    fail "INT 16H keyboard input not received (stub didn't see ENTER)"
fi

if grep -q "Invalid parameters" "$SCREEN_LOG"; then
    ok "SELECT.EXE executed (error message confirms it ran)"
else
    fail "SELECT.EXE did not execute (no error message found)"
fi

if grep -q "Rule 2: matched.*Invalid parameters" "$SCREEN_LOG"; then
    ok "SELECT.EXE rejected a missing mode and returned to DOS"
else
    fail "SELECT.EXE did not reject a missing mode safely"
fi
if grep -q "Rule 4: matched.*Invalid parameters" "$SCREEN_LOG"; then
    ok "SELECT.EXE rejected an unknown mode and returned to DOS"
else
    fail "SELECT.EXE did not reject an unknown mode safely"
fi
if grep -q "Rule 6: matched.*Invalid parameters" "$SCREEN_LOG"; then
    ok "SELECT.EXE rejected excess operands and returned to DOS"
else
    fail "SELECT.EXE did not reject excess operands safely"
fi
if grep -q "Rule 3: matched.*selectfdiskreturned" "$FDISK_SCREEN_LOG"; then
    ok "SELECT FDISK missing-control path preserved shell input and returned"
else
    fail "SELECT FDISK missing-control path did not preserve shell input"
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

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "--- screen log (for debugging) ---"
    cat "$SCREEN_LOG" 2>/dev/null || echo "(empty)"
    echo "--- SELECT MENU screen log ---"
    cat "$MENU_SCREEN_LOG" 2>/dev/null || echo "(empty)"
    echo "--- SELECT FDISK screen log ---"
    cat "$FDISK_SCREEN_LOG" 2>/dev/null || echo "(empty)"
    echo "--- end screen log ---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
