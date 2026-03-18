#!/bin/bash
# tests/test_recover.sh — E2E test for RECOVER file recovery via QEMU.
#
# RECOVER (RECOVER.ASM) has two modes:
#   RECOVER A:FILENAME  — file mode: walks FAT chain cluster-by-cluster,
#                         skipping bad sectors; prints "X of Y bytes recovered".
#   RECOVER A:          — drive mode: rebuilds entire directory, renaming
#                         all chains to FILExxxx.REC; prints "N file(s) recovered".
#                         Destructive — not tested here.
#
# Both modes call GetKeystroke via INT 21h/AH=0Ch/AL=8 (flush input buffer
# then read one char).  With CTTY AUX the read is from COM1 serial.
#
# The flush-then-read means a single pre-sent character may be discarded by
# the flush before the read.  We use a continuous stream of \r\n (every 0.5s)
# piped into QEMU stdin (→ emulated COM1) so a fresh character is always
# available after the flush completes.  This is the same pattern as
# test_misc_qemu.sh and avoids the serial_expect.py FIFO timing race.
#
# Run via: make test-recover  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/recover-boot.img"
SERIAL_LOG="$OUT/recover-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== RECOVER E2E tests (QEMU) ==="

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# ── Step 1: build test floppy ─────────────────────────────────────────────────
echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"

# Add a small text file for RECOVER to process.
# On a healthy floppy (no bad sectors) RECOVER reads all clusters cleanly
# and prints "X of X bytes recovered".
printf 'RECOVER TEST FILE CONTENTS\r\n' | mcopy -o -i "$BOOT_IMG" - ::TESTFILE.TXT

# AUTOEXEC.BAT: RECOVER A:TESTFILE.TXT in file mode (non-destructive).
{
    printf 'CTTY AUX\r\n'

    # ── RECOVER A:TESTFILE.TXT — file recovery ────────────────────────────────
    # Prompts "Press any key to begin recovery of the file(s) on drive A:"
    # then reads FAT chain and prints "X of Y bytes recovered".
    printf 'ECHO ---RECOVER-FILE---\r\n'
    printf 'RECOVER A:TESTFILE.TXT\r\n'
    printf 'ECHO RECOVER_FILE_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Step 2: boot QEMU and capture serial output ───────────────────────────────
# Continuous \r\n stream satisfies GetKeystroke's flush-then-read:
#   INT 21h/AH=0Ch/AL=8 flushes the input buffer then waits for a char.
#   A fresh \r arrives within 0.5s after the flush, unblocking RECOVER.
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

# ── Step 3: checks ────────────────────────────────────────────────────────────
echo ""
echo "--- RECOVER serial log checks ---"

if grep -qi "Press any key" "$SERIAL_LOG"; then
    ok "RECOVER (keypress prompt appeared on serial)"
else
    fail "RECOVER (keypress prompt not seen — CTTY AUX routing issue?)"
fi

if grep -qi "bytes recovered" "$SERIAL_LOG"; then
    ok "RECOVER A:TESTFILE.TXT ('bytes recovered' message printed)"
else
    fail "RECOVER A:TESTFILE.TXT (expected 'bytes recovered' in output)"
fi

if grep -q "RECOVER_FILE_DONE" "$SERIAL_LOG"; then
    ok "RECOVER A:TESTFILE.TXT (batch continued after recovery)"
else
    fail "RECOVER A:TESTFILE.TXT (batch hung or crashed)"
fi

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
