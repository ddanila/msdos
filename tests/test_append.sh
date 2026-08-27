#!/bin/bash
# tests/test_append.sh — E2E tests for APPEND.EXE via QEMU.
#
# APPEND behavior:
#   - First call: installs as TSR (INT 2Fh hook + INT 21h/AH=31h Keep_Process).
#     No output on success.
#   - /E (first-time-only): use DOS environment for path storage.
#   - /X (first-time-only): extend search to EXEC/FIND.
#   - Subsequent calls: process arguments and exit normally.
#   - APPEND [path]: set the append path.
#   - APPEND /PATH:ON: search appended dirs for files with explicit paths.
#   - APPEND ;: clear the append path (semicolon = null path list).
#   - APPEND (no args, after install): display current path to STDOUT.
#     Format: "APPEND=<path>" (display_dirs backs up 7 bytes to include "APPEND=").
#   - APPEND (no args, empty path): "No Append" message (msg 5) to STDERR —
#     NOT visible via CTTY AUX (CTTY redirects handles 0/1 only, not handle 2).
#
# Run via: make test-append  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

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

# ── Step 1: build boot floppy ────────────────────────────────────────────────
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

    # ── APPEND /E /X (first call) — install with environment and extended search ──
    # First-time-only flags. No output on success. Hooks INT 2Fh + INT 21h/AH=31h
    # Keep_Process. /E: store path in APPEND= environment variable.
    # /X: extend file search to EXEC and file-find operations.
    printf 'ECHO ---APPEND-INIT---\r\n'
    printf 'APPEND /E /X\r\n'
    printf 'ECHO APPEND_INIT_DONE\r\n'

    # ── APPEND C:\DOS (set path) — set the append path ────────────────────────
    # Second call: already_there path. Sets app_dirs buffer to "C:\DOS".
    # With /E active, also updates APPEND= in the environment.
    # No output on success.
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

    # ── APPEND (show current path) ─────────────────────────────────────────────
    # display_dirs: address_status → ES:DI = path buffer; sub si,7 includes
    # "APPEND=" prefix; print_STDOUT writes "APPEND=C:\DOS\r\n" to STDOUT.
    # Visible via CTTY AUX (STDOUT = handle 1, redirected to COM1).
    printf 'ECHO ---APPEND-SHOW---\r\n'
    printf 'APPEND\r\n'
    printf 'ECHO APPEND_SHOW_DONE\r\n'
    printf 'APPEND /E\r\n'
    printf 'IF ERRORLEVEL 1 ECHO APPEND_SECOND_E_REJECTED\r\n'

    # ── APPEND /PATH:ON — enable PATH mode ────────────────────────────────────
    # Sets Path_mode flag in mode_flags. No output.
    printf 'ECHO ---APPEND-PATH-ON---\r\n'
    printf 'APPEND /PATH:ON\r\n'
    printf 'ECHO APPEND_PATH_ON_DONE\r\n'
    printf 'TYPE SUB\\APNDATA.TXT\r\n'

    # ── APPEND /PATH:OFF — disable PATH mode ───────────────────────────────────
    # Clears Path_mode flag in mode_flags. No output.
    printf 'ECHO ---APPEND-PATH-OFF---\r\n'
    printf 'APPEND /PATH:OFF\r\n'
    printf 'ECHO APPEND_PATH_OFF_DONE\r\n'
    printf 'APPEND /PATH:MAYBE\r\n'
    printf 'IF ERRORLEVEL 1 ECHO APPEND_BAD_PATH_MODE_REJECTED\r\n'
    printf 'APPEND /X:MAYBE\r\n'
    printf 'IF ERRORLEVEL 1 ECHO APPEND_BAD_X_MODE_REJECTED\r\n'
    printf 'APPEND /Z\r\n'
    printf 'IF ERRORLEVEL 1 ECHO APPEND_UNKNOWN_REJECTED\r\n'

    # ── APPEND ; (clear path) ─────────────────────────────────────────────────
    # Semicolon as null path list → sets app_dirs to ";". No output.
    printf 'ECHO ---APPEND-SEMI---\r\n'
    printf 'APPEND ;\r\n'
    printf 'ECHO APPEND_SEMI_DONE\r\n'
    printf 'TYPE APNDATA.TXT\r\n'

    # ── APPEND (show empty path) ───────────────────────────────────────────────
    # display_dirs: app_dirs=";" → no_dirs_appended → "No Append" (msg 5) to
    # STDERR (handle 2). NOT visible via CTTY AUX. Batch continues.
    printf 'ECHO ---APPEND-EMPTY---\r\n'
    printf 'APPEND\r\n'
    printf 'ECHO APPEND_EMPTY_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Step 2: boot QEMU ─────────────────────────────────────────────────────────
# No interactive prompts from APPEND — continuous newline feed is harmless.
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

# ── Check output ──────────────────────────────────────────────────────────────

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

# display_dirs writes "APPEND=C:\DOS" to STDOUT (visible via CTTY AUX).
# The display_dirs code backs up 7 bytes from the path buffer to include
# "APPEND=" prefix (append_id = "APPEND=" immediately precedes app_dirs).
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

# The cleared-state status call must emit the source-defined diagnostic.
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
