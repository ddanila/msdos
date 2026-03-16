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

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

{
    printf 'CTTY AUX\r\n'

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
    printf 'APPEND C:\DOS\r\n'
    printf 'ECHO APPEND_PATH_DONE\r\n'

    # ── APPEND (show current path) ─────────────────────────────────────────────
    # display_dirs: address_status → ES:DI = path buffer; sub si,7 includes
    # "APPEND=" prefix; print_STDOUT writes "APPEND=C:\DOS\r\n" to STDOUT.
    # Visible via CTTY AUX (STDOUT = handle 1, redirected to COM1).
    printf 'ECHO ---APPEND-SHOW---\r\n'
    printf 'APPEND\r\n'
    printf 'ECHO APPEND_SHOW_DONE\r\n'

    # ── APPEND /PATH:ON — enable PATH mode ────────────────────────────────────
    # Sets Path_mode flag in mode_flags. No output.
    printf 'ECHO ---APPEND-PATH-ON---\r\n'
    printf 'APPEND /PATH:ON\r\n'
    printf 'ECHO APPEND_PATH_ON_DONE\r\n'

    # ── APPEND ; (clear path) ─────────────────────────────────────────────────
    # Semicolon as null path list → sets app_dirs to ";". No output.
    printf 'ECHO ---APPEND-SEMI---\r\n'
    printf 'APPEND ;\r\n'
    printf 'ECHO APPEND_SEMI_DONE\r\n'

    # ── APPEND (show empty path) ───────────────────────────────────────────────
    # display_dirs: app_dirs=";" → no_dirs_appended → "No Append" (msg 5) to
    # STDERR (handle 2). NOT visible via CTTY AUX. Batch continues.
    printf 'ECHO ---APPEND-EMPTY---\r\n'
    printf 'APPEND\r\n'
    printf 'ECHO APPEND_EMPTY_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
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
    ok "APPEND C:\\DOS (path set silently, batch continued)"
else
    fail "APPEND C:\\DOS (batch hung or crashed)"
fi

echo ""
echo "--- APPEND show path tests ---"

# display_dirs writes "APPEND=C:\DOS" to STDOUT (visible via CTTY AUX).
# The display_dirs code backs up 7 bytes from the path buffer to include
# "APPEND=" prefix (append_id = "APPEND=" immediately precedes app_dirs).
if grep -qi 'APPEND=C:\\DOS' "$SERIAL_LOG"; then
    ok "APPEND (show path: 'APPEND=C:\\DOS' printed to STDOUT)"
else
    fail "APPEND (expected 'APPEND=C:\\DOS' in output after setting path)"
fi

if grep -q "APPEND_SHOW_DONE" "$SERIAL_LOG"; then
    ok "APPEND (show path: batch continued)"
else
    fail "APPEND (show path: batch hung or crashed)"
fi

echo ""
echo "--- APPEND /PATH:ON tests ---"

if grep -q "APPEND_PATH_ON_DONE" "$SERIAL_LOG"; then
    ok "APPEND /PATH:ON (PATH mode set silently, batch continued)"
else
    fail "APPEND /PATH:ON (batch hung or crashed)"
fi

echo ""
echo "--- APPEND ; (clear path) tests ---"

if grep -q "APPEND_SEMI_DONE" "$SERIAL_LOG"; then
    ok "APPEND ; (path cleared silently, batch continued)"
else
    fail "APPEND ; (batch hung or crashed)"
fi

echo ""
echo "--- APPEND (empty path) tests ---"

# "No Append" message goes to STDERR (not visible via CTTY AUX).
# Just verify batch continues.
if grep -q "APPEND_EMPTY_DONE" "$SERIAL_LOG"; then
    ok "APPEND (empty path: batch continued — 'No Append' goes to STDERR, invisible)"
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
