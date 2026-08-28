#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

BOOT_IMG="$OUT/floppy-append-boot.img"
SERIAL_LOG="$OUT/append-serial.log"
EXIT_COM="$OUT/qemu-exit.com"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== APPEND E2E tests (QEMU) ==="

echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'MD APNDIR\r\n'
    printf 'MD APNDIR\\SUB\r\n'
    printf 'MD SUB\r\n'
    printf 'ECHO APPEND_OPEN_PAYLOAD>APNDIR\\APNDATA.TXT\r\n'
    printf 'ECHO APPEND_PATH_PAYLOAD>APNDIR\\SUB\\PATHDATA.TXT\r\n'
    printf 'COPY TREE.COM APNDIR\\APNDEXE.COM>NUL\r\n'

    printf 'ECHO ---APPEND-INIT---\r\n'
    printf 'APPEND /E /X\r\n'
    printf 'ECHO APPEND_INIT_DONE\r\n'

    printf 'ECHO ---APPEND-PATH---\r\n'
    printf 'APPEND A:\\APNDIR\r\n'
    printf 'ECHO APPEND_PATH_DONE\r\n'
    printf 'TYPE APNDATA.TXT\r\n'
    printf 'APPEND /X:OFF\r\n'
    printf 'IF NOT EXIST APNDATA.TXT ECHO APPEND_X_OFF_FIND_BLOCKED\r\n'
    printf 'APNDEXE /?\r\n'
    printf 'APPEND /X:ON\r\n'
    printf 'IF EXIST APNDATA.TXT ECHO APPEND_X_ON_FIND_OK\r\n'
    printf 'APNDEXE /?\r\n'
    printf 'ECHO APPEND_X_EXEC_DONE\r\n'

    printf 'ECHO ---APPEND-SHOW---\r\n'
    printf 'APPEND\r\n'
    printf 'ECHO APPEND_SHOW_DONE\r\n'
    printf 'APPEND /E\r\n'
    printf 'IF ERRORLEVEL 1 ECHO APPEND_SECOND_E_REJECTED\r\n'

    printf 'ECHO ---APPEND-PATH-ON---\r\n'
    printf 'APPEND /PATH:ON\r\n'
    printf 'ECHO APPEND_PATH_ON_DONE\r\n'
    printf 'TYPE SUB\\APNDATA.TXT\r\n'

    printf 'ECHO ---APPEND-PATH-OFF---\r\n'
    printf 'APPEND /PATH:OFF\r\n'
    printf 'ECHO APPEND_PATH_OFF_DONE\r\n'
    printf 'APPEND /PATH:MAYBE\r\n'
    printf 'IF ERRORLEVEL 1 ECHO APPEND_BAD_PATH_MODE_REJECTED\r\n'
    printf 'APPEND /X:MAYBE\r\n'
    printf 'IF ERRORLEVEL 1 ECHO APPEND_BAD_X_MODE_REJECTED\r\n'
    printf 'APPEND /Z\r\n'
    printf 'IF ERRORLEVEL 1 ECHO APPEND_UNKNOWN_REJECTED\r\n'

    printf 'ECHO ---APPEND-SEMI---\r\n'
    printf 'APPEND ;\r\n'
    printf 'ECHO APPEND_SEMI_DONE\r\n'
    printf 'TYPE APNDATA.TXT\r\n'

    printf 'ECHO ---APPEND-EMPTY---\r\n'
    printf 'APPEND\r\n'
    printf 'ECHO APPEND_EMPTY_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

echo "Booting QEMU (may take ~90s)..."
rm -f "$SERIAL_LOG"
(while true; do sleep 0.5; printf '\r\n'; done) | \
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi


echo ""
echo "--- APPEND /E /X (first call) tests ---"

if grep -q "APPEND_INIT_DONE" "$SERIAL_LOG"; then
    ok "APPEND /E /X (first call installed silently, batch continued)"
else
    fail "APPEND /E /X (batch hung or crashed after first APPEND call)"
fi

echo ""
echo "--- APPEND path set tests ---"

if grep -q "APPEND_PATH_DONE" "$SERIAL_LOG"; then
    ok "APPEND A:\\APNDIR (resident path set)"
else
    fail "APPEND A:\\APNDIR (batch hung or crashed)"
fi

echo ""
echo "--- APPEND show path tests ---"

if grep -qi 'APPEND=A:\\APNDIR' "$SERIAL_LOG"; then
    ok "APPEND /E exposes the environment-backed resident path"
else
    fail "APPEND did not expose its environment-backed resident path"
fi

if grep -q "APPEND_SHOW_DONE" "$SERIAL_LOG"; then
    ok "APPEND (show path: batch continued)"
else
    fail "APPEND (show path: batch hung or crashed)"
fi

if grep -q '^APPEND_OPEN_PAYLOAD' "$SERIAL_LOG"; then
    ok "APPEND extends ordinary OPEN lookup to the resident path"
else
    fail "APPEND ordinary OPEN lookup did not return the exact payload"
fi

if grep -q '^APPEND_X_OFF_FIND_BLOCKED' "$SERIAL_LOG" \
    && grep -q '^APPEND_X_ON_FIND_OK' "$SERIAL_LOG" \
    && grep -q 'Graphically displays the directory structure' "$SERIAL_LOG" \
    && grep -q '^APPEND_X_EXEC_DONE' "$SERIAL_LOG"; then
    ok "APPEND /X transitions gate FIND and EXEC lookup"
else
    fail "APPEND /X did not produce the expected FIND/EXEC transition"
fi

if grep -q 'Invalid switch -  /E' "$SERIAL_LOG"; then
    ok "APPEND diagnoses /E after resident installation"
else
    fail "APPEND did not diagnose first-load-only /E on a later invocation"
fi

echo ""
echo "--- APPEND /PATH:ON tests ---"

if grep -q "APPEND_PATH_ON_DONE" "$SERIAL_LOG"; then
    ok "APPEND /PATH:ON (PATH mode set silently, batch continued)"
else
    fail "APPEND /PATH:ON (batch hung or crashed)"
fi

if [[ $(grep -c '^APPEND_OPEN_PAYLOAD' "$SERIAL_LOG") -eq 2 ]]; then
    ok "APPEND /PATH:ON extends explicit-path OPEN lookup"
else
    fail "APPEND /PATH:ON did not resolve the explicit path to the appended filename"
fi

echo ""
echo "--- APPEND /PATH:OFF tests ---"

if grep -q "APPEND_PATH_OFF_DONE" "$SERIAL_LOG"; then
    ok "APPEND /PATH:OFF (PATH mode cleared silently, batch continued)"
else
    fail "APPEND /PATH:OFF (batch hung or crashed)"
fi

if grep -q 'Parameter value not allowed -  /PATH:MAYBE' "$SERIAL_LOG" \
    && grep -q 'Parameter value not allowed -  /X:MAYBE' "$SERIAL_LOG" \
    && grep -q 'Invalid switch -  /Z' "$SERIAL_LOG"; then
    ok "APPEND diagnoses invalid /PATH, /X, and unknown switch values"
else
    fail "APPEND invalid-switch diagnostics were incomplete"
fi

echo ""
echo "--- APPEND ; (clear path) tests ---"

if grep -q "APPEND_SEMI_DONE" "$SERIAL_LOG"; then
    ok "APPEND ; (path cleared silently, batch continued)"
else
    fail "APPEND ; (batch hung or crashed)"
fi

if grep -q 'File not found - APNDATA.TXT' "$SERIAL_LOG"; then
    ok "APPEND ; removes the resident OPEN search path"
else
    fail "APPEND ; left the cleared path active"
fi

echo ""
echo "--- APPEND (empty path) tests ---"

if grep -q 'No Append' "$SERIAL_LOG" && grep -q "APPEND_EMPTY_DONE" "$SERIAL_LOG"; then
    ok "APPEND reports the cleared resident path"
else
    fail "APPEND (empty path: batch hung or crashed)"
fi

echo ""
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
