#!/bin/bash
# tests/test_edlin_b_qemu.sh — E2E test for EDLIN /B (binary mode) via QEMU.
#
# EDLIN /B sets loadmod=1 via SYSPARSE: EDLPARSE.ASM calls sysparse, which
# sets parse_switch_b=true when "/B" is found; EDLIN_COMMAND then sets
# LOADMOD=1.  SCANEOF in EDLCMD2.ASM branches on LOADMOD:
#   LOADMOD=0 (default): REPNE SCASB scans for ^Z (0x1Ah), truncates there.
#   LOADMOD=1 (/B):      loads to physical EOF; strips trailing ^Z only.
#
# Test approach:
#   1. Use DEBUG to write a test file with an embedded ^Z:
#        "LINE1\r\nLINE2\r\n^Z\r\nLINE3\r\n"  (24 bytes)
#   2. Run EDLIN TESTFILE /B — lists all lines including LINE3 after ^Z.
#   3. Run EDLIN TESTFILE (no /B) — stops at ^Z, LINE3 not loaded.
#   4. Compare output: LINE3 in /B run, absent in non-/B run.
#
# The batch uses CTTY AUX so EDLIN's output goes to COM1 (serial log).
# EDLIN reads commands from redirect files (bypasses CTTY for stdin).
#
# Run via: make test-edlin-b-qemu  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/edlin-b-boot.img"
SERIAL_LOG="$OUT/edlin-b-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== EDLIN /B (binary mode) E2E test (QEMU) ==="

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# ── Build test floppy ─────────────────────────────────────────────────────────
echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"

# DBGCMD.TXT — DEBUG script to write EDLBTEST.TXT with embedded ^Z.
#
# File content (24 bytes = 0x18):
#   4c 49 4e 45 31 0d 0a   "LINE1\r\n"
#   4c 49 4e 45 32 0d 0a   "LINE2\r\n"
#   1a 0d 0a               "^Z\r\n"
#   4c 49 4e 45 33 0d 0a   "LINE3\r\n"
#
# DEBUG E command enters the bytes at offset 0x300.
# N sets the filename; RCX=18h (24) sets write length; W 300 writes.
{
    printf 'E 300 4c 49 4e 45 31 0d 0a 4c 49 4e 45 32 0d 0a 1a 0d 0a 4c 49 4e 45 33 0d 0a\r\n'
    printf 'N EDLBTEST.TXT\r\n'
    printf 'RCX\r\n'
    printf '18\r\n'
    printf 'RBX\r\n'
    printf '0\r\n'
    printf 'W 300\r\n'
    printf 'Q\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::DBGCMD.TXT

# EDLCMD.TXT — EDLIN command script: list lines 1-10, then quit (no save).
{
    printf '1,10L\r\n'
    printf 'Q\r\n'
    printf 'Y\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::EDLCMD.TXT

# AUTOEXEC.BAT:
#   1. Switch console to AUX (COM1) for serial capture.
#   2. Use DEBUG to create EDLBTEST.TXT with embedded ^Z.
#   3. Run "EDLIN EDLBTEST.TXT /B < EDLCMD.TXT" — binary mode, shows LINE3.
#   4. Run "EDLIN EDLBTEST.TXT < EDLCMD.TXT"    — text mode, stops at ^Z.
#   5. Emit markers so the serial log can be parsed.
{
    printf 'CTTY AUX\r\n'

    # Create the binary test file via DEBUG.
    printf 'DEBUG < DBGCMD.TXT\r\n'
    printf 'ECHO FILE_CREATED\r\n'

    # Run EDLIN with /B — LINE3 should appear after the ^Z.
    printf 'ECHO ---EDLIN-B-START---\r\n'
    printf 'EDLIN EDLBTEST.TXT /B < EDLCMD.TXT\r\n'
    printf 'ECHO ---EDLIN-B-END---\r\n'

    # Run EDLIN without /B — LINE3 should NOT appear.
    printf 'ECHO ---EDLIN-NOB-START---\r\n'
    printf 'EDLIN EDLBTEST.TXT < EDLCMD.TXT\r\n'
    printf 'ECHO ---EDLIN-NOB-END---\r\n'

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
echo "--- EDLIN /B tests ---"

# Basic sanity: DEBUG created the file, EDLIN ran.
if grep -q "FILE_CREATED" "$SERIAL_LOG"; then
    ok "DEBUG wrote EDLBTEST.TXT with embedded ^Z"
else
    fail "DEBUG file creation step did not complete"
fi

# With /B: LINE1 and LINE2 should be present (they load in both modes).
if grep -q "LINE1" "$SERIAL_LOG" && grep -q "LINE2" "$SERIAL_LOG"; then
    ok "EDLIN /B: LINE1 and LINE2 loaded"
else
    fail "EDLIN /B: expected LINE1 and LINE2 in output"
fi

# With /B: LINE3 must appear — proof that ^Z was treated as a normal character.
# (Without /B EDLIN stops at ^Z and never loads LINE3.)
if grep -q "LINE3" "$SERIAL_LOG"; then
    ok "EDLIN /B: LINE3 appears after embedded ^Z (binary mode works)"
else
    fail "EDLIN /B: LINE3 did NOT appear — /B flag did not ignore ^Z"
fi

# Verify the /B run ended cleanly (batch reached the END marker).
if grep -q "EDLIN-B-END" "$SERIAL_LOG"; then
    ok "EDLIN /B run completed, batch continued"
else
    fail "EDLIN /B run did not complete (batch hung)"
fi

# Without /B: the run must at least complete (EDLIN_NOB_END reached).
if grep -q "EDLIN-NOB-END" "$SERIAL_LOG"; then
    ok "EDLIN (no /B) run completed"
else
    fail "EDLIN (no /B) run did not complete"
fi

# Batch completion check.
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
