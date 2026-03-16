#!/bin/bash
# tests/test_diskcomp_diskcopy.sh — E2E tests for DISKCOPY.COM and DISKCOMP.COM via QEMU.
#
# Flow:
#   1. Build boot floppy (A:) = floppy.img + AUTOEXEC.BAT
#   2. Build target floppy (B:) = pre-formatted blank FAT12 (mformat)
#   3. Boot QEMU with A: = boot, B: = blank target; feed continuous "N\r\n"
#      through -serial stdio to satisfy:
#        - PRESS_ANY_KEY before each operation (CLEAR_BUF + any char → 'N' OK)
#        - "Copy another diskette (Y/N)?" and "Compare another diskette (Y/N)?"
#          (CLEAR_BUF + KEY_IN_ECHO → must feed 'N', not bare CR which is invalid)
#   4. Check COM1 serial output for expected messages
#
# Interactive prompt analysis (DISKCOPY/DISKCOMP source verified):
#   DISKCOPY two-drive (A:≠B:) flow per invocation:
#     - Print "Insert SOURCE diskette in drive A:" (no wait)
#     - Print "Insert TARGET diskette in drive B:" (no wait)
#     - PRESS_ANY_KEY ("Press any key to continue...") — CLEAR_BUF + KEY_IN (1 char, any)
#     - Copy tracks, print "Copying %1 tracks..."
#     - "Copy another diskette (Y/N)?" — CLEAR_BUF + KEY_IN_ECHO (needs 'N')
#     NOTE: "Copy process ended" (msg 21) is FATAL_ERROR, not a success print.
#   DISKCOMP two-drive (A:≠B:) flow per invocation:
#     - Print "Insert FIRST diskette in drive A:" (no wait)
#     - Print "Insert SECOND diskette in drive B:" (no wait)
#     - PRESS_ANY_KEY — CLEAR_BUF + KEY_IN (1 char, any)
#     - Compare tracks, print "Comparing %1 tracks..."
#     - "Compare OK" (if identical) or "Compare error on..." (if different)
#     - "Compare process ended"
#     - "Compare another diskette (Y/N)?" — CLEAR_BUF + KEY_IN_ECHO (needs 'N')
#
# DISKCOMP exit codes: 0 = normal (even with compare errors), 1 = param error,
#   2 = Ctrl-Break. Compare errors do NOT set non-zero errorlevel.
#   "Compare OK" vs "Compare error on" in output is the test oracle.
#
# Run via: make test-diskcomp-diskcopy  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/floppy-diskcomp-boot.img"
TARGET_IMG="$OUT/floppy-diskcomp-target.img"
SERIAL_LOG="$OUT/diskcomp-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== DISKCOPY / DISKCOMP E2E tests (QEMU) ==="

# ── Step 1: build boot floppy ────────────────────────────────────────────────
echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

{
    printf 'CTTY AUX\r\n'

    # ── DISKCOPY A: B: — copy boot floppy to blank target ─────────────────────
    # Prompts: PRESS_ANY_KEY (1 char) + COPY_ANOTHER (Y/N = 'N').
    # Output: "Copying 80 tracks", "18 Sectors/Track, 2 Side(s)", "Copy process ended".
    printf 'ECHO ---DISKCOPY---\r\n'
    printf 'DISKCOPY A: B:\r\n'
    printf 'ECHO DISKCOPY_DONE\r\n'

    # ── DISKCOMP A: B: (match) — compare identical disks ──────────────────────
    # After DISKCOPY, A: and B: are identical byte-for-byte.
    # Prompts: PRESS_ANY_KEY (1 char) + COMP_ANOTHER (Y/N = 'N').
    # Output: "Comparing 80 tracks", "Compare OK", "Compare process ended".
    printf 'ECHO ---DISKCOMP-MATCH---\r\n'
    printf 'DISKCOMP A: B:\r\n'
    printf 'ECHO DISKCOMP_MATCH_DONE\r\n'

    # ── Modify A: — write a new file to create difference ─────────────────────
    # ECHO writes to DISKTEST.TXT on A:, changing FAT + directory + data sectors.
    printf 'ECHO DISKTEST > DISKTEST.TXT\r\n'

    # ── DISKCOMP A: B: (mismatch) — compare after modification ────────────────
    # A: now has DISKTEST.TXT; B: does not. Sectors differ → "Compare error on".
    # DISKCOMP errorlevel stays 0 on compare errors — must check output text.
    printf 'ECHO ---DISKCOMP-DIFF---\r\n'
    printf 'DISKCOMP A: B:\r\n'
    printf 'ECHO DISKCOMP_DIFF_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Step 2: create pre-formatted blank target floppy ─────────────────────────
# mformat writes a valid FAT12 filesystem on B:.
# DISKCOPY writes raw tracks via IOCTL (not filesystem), so mformat vs. zero
# makes no difference for the copy; FAT12 is needed so DISKTEST.TXT ECHO works.
dd if=/dev/zero bs=512 count=2880 of="$TARGET_IMG" status=none
mformat -i "$TARGET_IMG" -f 1440 ::

# ── Step 3: boot QEMU, run tests ─────────────────────────────────────────────
# Feed continuous "N\r\n" to satisfy both PRESS_ANY_KEY (any char) and Y/N prompts.
# CLEAR_BUF (INT 21h/AH=0Ch) before each Y/N read flushes the type-ahead buffer,
# so timing of feeds is not critical — each prompt gets a fresh 'N' after the flush.
echo "Booting QEMU with A:=boot B:=blank target (may take ~90s)..."
rm -f "$SERIAL_LOG"
(while true; do sleep 0.2; printf 'N\r\n'; done) | \
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

# ── Check output ──────────────────────────────────────────────────────────────

echo ""
echo "--- DISKCOPY tests ---"

# "Copying 80 tracks" (or similar — exact track count from disk BPB)
if grep -qi "Copying.*tracks" "$SERIAL_LOG"; then
    ok "DISKCOPY A: B: (started copying tracks)"
else
    fail "DISKCOPY A: B: (expected 'Copying...tracks' message)"
fi

# "Copy another diskette (Y/N)?" — printed after successful copy, before exit
if grep -qi "Copy another diskette" "$SERIAL_LOG"; then
    ok "DISKCOPY A: B: (copy completed, reached repeat prompt)"
else
    fail "DISKCOPY A: B: (expected 'Copy another diskette' prompt after successful copy)"
fi

if grep -q "DISKCOPY_DONE" "$SERIAL_LOG"; then
    ok "DISKCOPY A: B: (batch continued after DISKCOPY)"
else
    fail "DISKCOPY A: B: (batch hung or crashed after DISKCOPY)"
fi

echo ""
echo "--- DISKCOMP (match) tests ---"

# "Comparing 80 tracks" — printed after reading source disk geometry
if grep -qi "Comparing.*tracks" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: match (started comparing tracks)"
else
    fail "DISKCOMP A: B: match (expected 'Comparing...tracks' message)"
fi

# "Compare OK" — printed when no compare errors found
if grep -qi "Compare OK" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: match (identical disks reported 'Compare OK')"
else
    fail "DISKCOMP A: B: match (expected 'Compare OK' for identical disks)"
fi

if grep -q "DISKCOMP_MATCH_DONE" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: match (batch continued)"
else
    fail "DISKCOMP A: B: match (batch hung or crashed)"
fi

echo ""
echo "--- DISKCOMP (mismatch) tests ---"

# "Compare error on" — printed per-track when sectors differ
if grep -qi "Compare error on" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: mismatch (detected 'Compare error on' after file write)"
else
    fail "DISKCOMP A: B: mismatch (expected 'Compare error on' after DISKTEST.TXT write)"
fi

if grep -q "DISKCOMP_DIFF_DONE" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: mismatch (batch continued)"
else
    fail "DISKCOMP A: B: mismatch (batch hung or crashed)"
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
