#!/bin/bash
# tests/test_backup_restore.sh — E2E tests for BACKUP.COM and RESTORE.COM via QEMU.
#
# Flow:
#   1. Build boot floppy (A:) = floppy.img + test files + AUTOEXEC.BAT
#   2. Build target floppy (B:) = pre-formatted blank FAT12 (mformat)
#   3. Boot QEMU with A: = boot, B: = backup target; feed continuous newlines
#      through -serial stdio to satisfy all "Press any key to continue" prompts
#   4. Check COM1 serial output for expected messages
#
# Interactive prompt analysis (BACKUP.COM source verified):
#   Every BACKUP call prompts via display_it(..., WAIT):
#     - INSERTSOURCE ("Insert backup source diskette in drive A:") — always, 1 wait
#     - INSERTTARGET ("Insert backup diskette 1 in drive B:")      — if target used
#     - ERASEMSG     ("WARNING! Files in target drive will be erased") — if target used
#   /A (append) replaces INSERTTARGET+ERASEMSG with LASTDISKMSG (1 wait).
#   No-files case: only INSERTSOURCE (1 wait), then "No files found" message.
#   The "Press any key to continue . . ." suffix is added by display_it(WAIT).
#   RESTORE has similar prompts for multi-disk restore; single-disk is prompt-free.
#
# Run via: make test-backup-restore  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/floppy-backup-boot.img"
TARGET_IMG="$OUT/floppy-backup-target.img"
SERIAL_LOG="$OUT/backup-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== BACKUP / RESTORE E2E tests (QEMU) ==="

# ── Step 1: build boot floppy ────────────────────────────────────────────────
echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# Source files for backup tests.
printf 'BACKUP_FILE_ONE\r\n\x1a' | mcopy -o -i "$BOOT_IMG" - ::BAKF1.TXT
printf 'BACKUP_FILE_TWO\r\n\x1a' | mcopy -o -i "$BOOT_IMG" - ::BAKF2.TXT
printf 'DEEP_FILE\r\n\x1a'       | mcopy -o -i "$BOOT_IMG" - ::BAKDEEP.TXT

{
    printf 'CTTY AUX\r\n'

    # ── Setup: create source dir with test files ───────────────────────────────
    printf 'MD BAKSRC\r\n'
    printf 'COPY BAKF1.TXT BAKSRC\\FILE1.TXT\r\n'
    printf 'COPY BAKF2.TXT BAKSRC\\FILE2.TXT\r\n'

    # ── BACKUP basic: specific file spec to B: ────────────────────────────────
    # Prompts: INSERTSOURCE (1) + INSERTTARGET + ERASEMSG (2) = 3 keypresses.
    # Output: "*** Backing up files to drive B: ***"
    printf 'ECHO ---BACKUP-BASIC---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B:\r\n'
    printf 'ECHO BACKUP_BASIC_DONE\r\n'

    # ── BACKUP /S: include subdirectories ─────────────────────────────────────
    printf 'ECHO ---BACKUP-S---\r\n'
    printf 'MD BAKSRC\\SUB\r\n'
    printf 'COPY BAKDEEP.TXT BAKSRC\\SUB\\DEEP.TXT\r\n'
    printf 'BACKUP A:BAKSRC B: /S\r\n'
    printf 'ECHO BACKUP_S_DONE\r\n'

    # ── BACKUP /M: only files with archive bit set ────────────────────────────
    # Clear archive on FILE1, set on FILE2 — only FILE2 should be backed up.
    printf 'ECHO ---BACKUP-M---\r\n'
    printf 'ATTRIB -A BAKSRC\\FILE1.TXT\r\n'
    printf 'ATTRIB -A BAKSRC\\FILE2.TXT\r\n'
    printf 'ATTRIB +A BAKSRC\\FILE2.TXT\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /M\r\n'
    printf 'ECHO BACKUP_M_DONE\r\n'

    # ── BACKUP /A: append to existing backup, do not erase B:\BACKUP ─────────
    # Prompts: INSERTSOURCE (1) + LASTDISKMSG (1) = 2 keypresses.
    printf 'ECHO ---BACKUP-A---\r\n'
    printf 'COPY BAKF1.TXT BAKSRC\\EXTRA.TXT\r\n'
    printf 'BACKUP A:BAKSRC\\EXTRA.TXT B: /A\r\n'
    printf 'ECHO BACKUP_A_DONE\r\n'
    printf 'DEL BAKSRC\\EXTRA.TXT\r\n'

    # ── BACKUP no files: non-matching spec → warning + errorlevel 1 ──────────
    # Prompts: INSERTSOURCE only (1 keypress); get_diskette() never called.
    printf 'ECHO ---BACKUP-NOFILES---\r\n'
    printf 'BACKUP A:BAKSRC\\*.XYZ B:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO BACKUP_NOFIL_ERRORLEVEL\r\n'
    printf 'ECHO BACKUP_NOFIL_DONE\r\n'

    # ── RESTORE basic: round-trip FILE1 ──────────────────────────────────────
    # Back up FILE1 fresh, delete it, restore, verify it exists.
    printf 'ECHO ---RESTORE-BASIC---\r\n'
    printf 'BACKUP A:BAKSRC\\FILE1.TXT B:\r\n'
    printf 'DEL BAKSRC\\FILE1.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\FILE1.TXT\r\n'
    printf 'IF EXIST BAKSRC\\FILE1.TXT ECHO RESTORE_BASIC_OK\r\n'
    printf 'ECHO RESTORE_BASIC_DONE\r\n'

    # ── RESTORE /S: restore subdirectory tree ─────────────────────────────────
    printf 'ECHO ---RESTORE-S---\r\n'
    printf 'BACKUP A:BAKSRC B: /S\r\n'
    printf 'DEL BAKSRC\\SUB\\DEEP.TXT\r\n'
    printf 'RD BAKSRC\\SUB\r\n'
    printf 'RESTORE B: A:BAKSRC /S\r\n'
    printf 'IF EXIST BAKSRC\\SUB\\DEEP.TXT ECHO RESTORE_S_OK\r\n'
    printf 'ECHO RESTORE_S_DONE\r\n'

    # ── RESTORE /N: only restore files not present on destination ────────────
    # FILE2 is deleted; FILE1 is present — only FILE2 should be restored.
    printf 'ECHO ---RESTORE-N---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B:\r\n'
    printf 'DEL BAKSRC\\FILE2.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /N\r\n'
    printf 'IF EXIST BAKSRC\\FILE2.TXT ECHO RESTORE_N_OK\r\n'
    printf 'ECHO RESTORE_N_DONE\r\n'

    # ── Cleanup ────────────────────────────────────────────────────────────────
    printf 'DEL BAKSRC\\FILE1.TXT\r\n'
    printf 'DEL BAKSRC\\FILE2.TXT\r\n'
    printf 'DEL BAKSRC\\SUB\\DEEP.TXT\r\n'
    printf 'RD BAKSRC\\SUB\r\n'
    printf 'RD BAKSRC\r\n'

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Step 2: create pre-formatted blank target floppy ─────────────────────────
# mformat writes a valid FAT12 filesystem — BACKUP needs a writable FS on B:.
# (format_target() in BACKUP.C only calls FORMAT.COM if disk_free_space() fails;
# a mformatted disk has a valid FAT so it skips the FORMAT step.)
dd if=/dev/zero bs=512 count=2880 of="$TARGET_IMG" status=none
mformat -i "$TARGET_IMG" -f 1440 ::

# ── Step 3: boot QEMU, run tests ─────────────────────────────────────────────
# Feed continuous newlines through -serial stdio to satisfy all PRESS_ANY_KEY
# prompts from BACKUP (INSERTSOURCE, INSERTTARGET, ERASEMSG, LASTDISKMSG).
# Each BACKUP call needs up to 3 keypresses; newlines arrive every 0.2s.
# COMMAND.COM reads batch commands from the .BAT file (not stdin), so extra
# buffered newlines don't affect batch execution.
echo "Booting QEMU with A:=boot B:=blank target (may take ~90s)..."
rm -f "$SERIAL_LOG"
(while true; do sleep 0.2; printf '\r\n'; done) | \
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
echo "--- BACKUP tests ---"

# "*** Backing up files to drive B: ***" is printed by BUDISKMSG on every successful run
if grep -q "Backing up files to drive B" "$SERIAL_LOG"; then
    ok "BACKUP basic (started backing up to B:)"
else
    fail "BACKUP basic (expected 'Backing up files to drive B')"
fi

if grep -q "BACKUP_BASIC_DONE" "$SERIAL_LOG"; then
    ok "BACKUP basic (batch continued after BACKUP)"
else
    fail "BACKUP basic (batch hung or crashed)"
fi

if grep -q "BACKUP_S_DONE" "$SERIAL_LOG"; then
    ok "BACKUP /S (batch continued)"
else
    fail "BACKUP /S (batch hung or crashed)"
fi

if grep -q "BACKUP_M_DONE" "$SERIAL_LOG"; then
    ok "BACKUP /M (batch continued)"
else
    fail "BACKUP /M (batch hung or crashed)"
fi

if grep -q "BACKUP_A_DONE" "$SERIAL_LOG"; then
    ok "BACKUP /A (append mode — batch continued)"
else
    fail "BACKUP /A (batch hung or crashed)"
fi

# "Warning! No files were found to back up" — printed when spec matches nothing
if grep -qi "No files were found to back up" "$SERIAL_LOG"; then
    ok "BACKUP no-match (printed warning)"
else
    fail "BACKUP no-match (expected 'No files were found to back up')"
fi

if grep -q "BACKUP_NOFIL_ERRORLEVEL" "$SERIAL_LOG"; then
    ok "BACKUP no-match (errorlevel 1 set)"
else
    fail "BACKUP no-match (expected errorlevel >= 1)"
fi

echo ""
echo "--- RESTORE tests ---"

# "*** Files were backed up <date> ***" — RESTORE prints this before restoring
if grep -q "Files were backed up" "$SERIAL_LOG"; then
    ok "RESTORE basic (printed backup date header)"
else
    fail "RESTORE basic (expected 'Files were backed up')"
fi

if grep -q "RESTORE_BASIC_OK" "$SERIAL_LOG"; then
    ok "RESTORE basic (FILE1 restored to A:)"
else
    fail "RESTORE basic (FILE1 not found after RESTORE)"
fi

if grep -q "RESTORE_BASIC_DONE" "$SERIAL_LOG"; then
    ok "RESTORE basic (batch continued)"
else
    fail "RESTORE basic (batch hung or crashed)"
fi

if grep -q "RESTORE_S_OK" "$SERIAL_LOG"; then
    ok "RESTORE /S (DEEP.TXT restored in subdir)"
else
    fail "RESTORE /S (expected BAKSRC\\SUB\\DEEP.TXT to be restored)"
fi

if grep -q "RESTORE_N_OK" "$SERIAL_LOG"; then
    ok "RESTORE /N (restored only missing FILE2)"
else
    fail "RESTORE /N (expected FILE2 to be restored)"
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
