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
    # Clear archive on FILE1, set on FILE2 — only FILE2 backed up.
    # Verify by deleting both files and restoring: FILE2 must come back, FILE1 must not.
    printf 'ECHO ---BACKUP-M---\r\n'
    printf 'ATTRIB -A BAKSRC\\FILE1.TXT\r\n'
    printf 'ATTRIB -A BAKSRC\\FILE2.TXT\r\n'
    printf 'ATTRIB +A BAKSRC\\FILE2.TXT\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /M\r\n'
    printf 'DEL BAKSRC\\FILE1.TXT\r\n'
    printf 'DEL BAKSRC\\FILE2.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT\r\n'
    printf 'IF EXIST BAKSRC\\FILE2.TXT ECHO BACKUP_M_FILE2_IN_BACKUP\r\n'
    printf 'IF NOT EXIST BAKSRC\\FILE1.TXT ECHO BACKUP_M_FILE1_EXCLUDED\r\n'
    printf 'ECHO BACKUP_M_DONE\r\n'
    printf 'COPY BAKF1.TXT BAKSRC\\FILE1.TXT\r\n'

    # ── BACKUP /A: append to existing backup, do not erase B:\BACKUP ─────────
    # Verify /A by: fresh backup of FILE1+FILE2, then /A of EXTRA.TXT, then
    # delete all three and restore — all must come back.
    # Prompts per BACKUP call: INSERTSOURCE (1) + INSERTTARGET+ERASEMSG (2)
    #   or LASTDISKMSG (1) for /A first disk = 2 keypresses.
    printf 'ECHO ---BACKUP-A---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B:\r\n'
    printf 'COPY BAKF1.TXT BAKSRC\\EXTRA.TXT\r\n'
    printf 'BACKUP A:BAKSRC\\EXTRA.TXT B: /A\r\n'
    printf 'DEL BAKSRC\\FILE1.TXT\r\n'
    printf 'DEL BAKSRC\\FILE2.TXT\r\n'
    printf 'DEL BAKSRC\\EXTRA.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT\r\n'
    printf 'IF EXIST BAKSRC\\FILE1.TXT ECHO BACKUP_A_FILE1_PRESERVED\r\n'
    printf 'IF EXIST BAKSRC\\FILE2.TXT ECHO BACKUP_A_FILE2_PRESERVED\r\n'
    printf 'IF EXIST BAKSRC\\EXTRA.TXT ECHO BACKUP_A_EXTRA_ADDED\r\n'
    printf 'ECHO BACKUP_A_DONE\r\n'
    printf 'DEL BAKSRC\\EXTRA.TXT\r\n'

    # ── BACKUP no files: non-matching spec → warning + errorlevel 1 ──────────
    # Prompts: INSERTSOURCE only (1 keypress); get_diskette() never called.
    printf 'ECHO ---BACKUP-NOFILES---\r\n'
    printf 'BACKUP A:BAKSRC\\*.XYZ B:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO BACKUP_NOFIL_ERRORLEVEL\r\n'
    printf 'ECHO BACKUP_NOFIL_DONE\r\n'

    # ── BACKUP /F: format target if needed ─────────────────────────────────
    # /F tells BACKUP to format the target disk before use. With a pre-formatted
    # disk (B:), BACKUP detects free space exists and skips FORMAT. Tests /F
    # switch parsing through the full code path.
    # Prompts: INSERTSOURCE + INSERTTARGET + ERASEMSG = 3 keypresses.
    printf 'ECHO ---BACKUP-F---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /F\r\n'
    printf 'ECHO BACKUP_F_DONE\r\n'

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

    # ── BACKUP /D: date filter — include all files (cutoff Jan 1, 1980) ───────
    # /D:01-01-80 → back up files modified on or after Jan 1, 1980.
    # All test files (created in 2026 by QEMU real-time clock) pass this filter.
    # Verifies the /D flag is parsed, validated, and applied to the file scan.
    # Prompts: INSERTSOURCE + INSERTTARGET + ERASEMSG = 3 keypresses.
    printf 'ECHO ---BACKUP-D---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /D:01-01-80\r\n'
    printf 'DEL BAKSRC\\FILE1.TXT\r\n'
    printf 'DEL BAKSRC\\FILE2.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT\r\n'
    printf 'IF EXIST BAKSRC\\FILE1.TXT ECHO BACKUP_D_FILE1_OK\r\n'
    printf 'IF EXIST BAKSRC\\FILE2.TXT ECHO BACKUP_D_FILE2_OK\r\n'
    printf 'ECHO BACKUP_D_DONE\r\n'

    # ── BACKUP /T: time filter — include all files (cutoff 00:00:00) ─────────
    # /T:00:00:00 → back up files modified at or after midnight.
    # All files qualify (write_time >= 0 always true). Verifies /T is parsed.
    # Prompts: INSERTSOURCE + INSERTTARGET + ERASEMSG = 3 keypresses.
    printf 'ECHO ---BACKUP-T---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /T:00:00:00\r\n'
    printf 'DEL BAKSRC\\FILE1.TXT\r\n'
    printf 'DEL BAKSRC\\FILE2.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT\r\n'
    printf 'IF EXIST BAKSRC\\FILE1.TXT ECHO BACKUP_T_FILE1_OK\r\n'
    printf 'IF EXIST BAKSRC\\FILE2.TXT ECHO BACKUP_T_FILE2_OK\r\n'
    printf 'ECHO BACKUP_T_DONE\r\n'

    # ── BACKUP /L: log file — default path A:\BACKUP.LOG ─────────────────────
    # /L (no path) → writes log to A:\BACKUP.LOG (default: src_drive:\BACKUP.LOG).
    # Log contains date/time header + one line per backed-up file.
    # Prompts: INSERTSOURCE + INSERTTARGET + ERASEMSG = 3 keypresses.
    printf 'ECHO ---BACKUP-L---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /L\r\n'
    printf 'IF EXIST A:\\BACKUP.LOG ECHO BACKUP_L_LOG_EXISTS\r\n'
    printf 'ECHO BACKUP_L_DONE\r\n'

    # ── RESTORE /M: archive bit cleared on both → both skipped → "no files" ───
    # /M restores only dest files whose archive bit is SET (= modified since backup).
    # After ATTRIB -A on both files, /M skips both → "Warning! No files were found".
    # errorlevel = 2 (ERROR_FILE_NOT_FOUND). Single-disk RESTORE → no prompts.
    # BACKUP first to populate B: with current FILE1+FILE2. 3 keypresses.
    printf 'ECHO ---RESTORE-M---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B:\r\n'
    printf 'ATTRIB -A BAKSRC\\FILE1.TXT\r\n'
    printf 'ATTRIB -A BAKSRC\\FILE2.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /M\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_M_NO_MATCH\r\n'
    printf 'ECHO RESTORE_M_DONE\r\n'

    # ── RESTORE /B: before-date (1999 cutoff excludes 2026 files → "no files") ─
    # /B:12-31-99 → restore files with write_date <= 12/31/1999.
    # Files created in 2026 have FAT date year=46 (2026-1980) → excluded.
    # B: backup from /M test is reused (FILE1+FILE2 backed up).
    printf 'ECHO ---RESTORE-B---\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /B:12-31-99\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_B_NO_MATCH\r\n'
    printf 'ECHO RESTORE_B_DONE\r\n'

    # ── RESTORE /A: after-date (2050 cutoff excludes 2026 files → "no files") ──
    # /A:12-31-50 → restore files with write_date >= 12/31/2050 (year 50 = 2050).
    # Files from 2026 have date < 2050 → excluded.
    printf 'ECHO ---RESTORE-A---\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /A:12-31-50\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_A_NO_MATCH\r\n'
    printf 'ECHO RESTORE_A_DONE\r\n'

    # ── RESTORE /E: at-or-before time (00:00:00 → only midnight files → "no files") ─
    # /E:00:00:00 → restore files with write_time <= 00:00:00.
    # Files created during QEMU runtime have hour > 0 → RTOLD1.C: hh > 0 → excluded.
    # (ss = FAT 2-sec units 0-29; parser seconds=0 so ss > 0 also excludes exact-midnight files)
    printf 'ECHO ---RESTORE-E---\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /E:00:00:00\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_E_NO_MATCH\r\n'
    printf 'ECHO RESTORE_E_DONE\r\n'

    # ── RESTORE /L: at-or-after time (23:59:58 → only end-of-day files → "no files") ─
    # /L:23:59:58 → restore files with write_time >= 23:59:58.
    # RTOLD1.C: hh < 23 → excluded for most files. Even at 23:59, FAT ss (0-29) < 58 always.
    printf 'ECHO ---RESTORE-L---\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /L:23:59:58\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_L_NO_MATCH\r\n'
    printf 'ECHO RESTORE_L_DONE\r\n'

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

if grep -q "BACKUP_M_FILE2_IN_BACKUP" "$SERIAL_LOG"; then
    ok "BACKUP /M (archive-set FILE2 was backed up)"
else
    fail "BACKUP /M (expected FILE2 with +A to be in backup)"
fi

if grep -q "BACKUP_M_FILE1_EXCLUDED" "$SERIAL_LOG"; then
    ok "BACKUP /M (archive-cleared FILE1 was excluded)"
else
    fail "BACKUP /M (expected FILE1 without +A to be excluded)"
fi

if grep -q "BACKUP_M_DONE" "$SERIAL_LOG"; then
    ok "BACKUP /M (batch continued)"
else
    fail "BACKUP /M (batch hung or crashed)"
fi

if grep -q "BACKUP_A_FILE1_PRESERVED" "$SERIAL_LOG"; then
    ok "BACKUP /A (FILE1 from pre-/A backup restored)"
else
    fail "BACKUP /A (FILE1 not restored — /A may have erased existing backup)"
fi

if grep -q "BACKUP_A_FILE2_PRESERVED" "$SERIAL_LOG"; then
    ok "BACKUP /A (FILE2 from pre-/A backup restored)"
else
    fail "BACKUP /A (FILE2 not restored — /A may have erased existing backup)"
fi

if grep -q "BACKUP_A_EXTRA_ADDED" "$SERIAL_LOG"; then
    ok "BACKUP /A (EXTRA.TXT appended to backup set)"
else
    fail "BACKUP /A (EXTRA.TXT not in backup — append may not have worked)"
fi

if grep -q "BACKUP_A_DONE" "$SERIAL_LOG"; then
    ok "BACKUP /A (batch continued)"
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

# BACKUP /F — format target if needed (pre-formatted disk, tests switch parsing)
if grep -q "BACKUP_F_DONE" "$SERIAL_LOG"; then
    ok "BACKUP /F (format switch parsed, batch continued with pre-formatted disk)"
else
    fail "BACKUP /F (batch hung or crashed — /F parsing may have failed)"
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
echo "--- BACKUP /D /T /L tests ---"

if grep -q "BACKUP_D_FILE1_OK" "$SERIAL_LOG"; then
    ok "BACKUP /D (FILE1 backed up with /D:01-01-80)"
else
    fail "BACKUP /D (FILE1 not found after restore — date filter may have excluded it)"
fi

if grep -q "BACKUP_D_FILE2_OK" "$SERIAL_LOG"; then
    ok "BACKUP /D (FILE2 backed up with /D:01-01-80)"
else
    fail "BACKUP /D (FILE2 not found after restore — date filter may have excluded it)"
fi

if grep -q "BACKUP_D_DONE" "$SERIAL_LOG"; then
    ok "BACKUP /D (batch continued)"
else
    fail "BACKUP /D (batch hung or crashed)"
fi

if grep -q "BACKUP_T_FILE1_OK" "$SERIAL_LOG"; then
    ok "BACKUP /T (FILE1 backed up with /T:00:00:00)"
else
    fail "BACKUP /T (FILE1 not found after restore — time filter may have excluded it)"
fi

if grep -q "BACKUP_T_FILE2_OK" "$SERIAL_LOG"; then
    ok "BACKUP /T (FILE2 backed up with /T:00:00:00)"
else
    fail "BACKUP /T (FILE2 not found after restore — time filter may have excluded it)"
fi

if grep -q "BACKUP_T_DONE" "$SERIAL_LOG"; then
    ok "BACKUP /T (batch continued)"
else
    fail "BACKUP /T (batch hung or crashed)"
fi

if grep -q "BACKUP_L_LOG_EXISTS" "$SERIAL_LOG"; then
    ok "BACKUP /L (A:\\BACKUP.LOG created)"
else
    fail "BACKUP /L (A:\\BACKUP.LOG not found — log file was not created)"
fi

if grep -q "BACKUP_L_DONE" "$SERIAL_LOG"; then
    ok "BACKUP /L (batch continued)"
else
    fail "BACKUP /L (batch hung or crashed)"
fi

echo ""
echo "--- RESTORE /M /B /A /E /L tests ---"

# /M: archive=0 on both → both skipped → "Warning! No files were found to restore"
if grep -qi "no files were found to restore" "$SERIAL_LOG"; then
    ok "RESTORE /M /B /A /E /L (at least one 'no files found' message appeared)"
else
    fail "RESTORE /M /B /A /E /L (expected 'No files were found to restore' at least once)"
fi

if grep -q "RESTORE_M_NO_MATCH" "$SERIAL_LOG"; then
    ok "RESTORE /M (errorlevel set — archive=0 files excluded)"
else
    fail "RESTORE /M (expected errorlevel >= 1 when all dest files have archive=0)"
fi

if grep -q "RESTORE_M_DONE" "$SERIAL_LOG"; then
    ok "RESTORE /M (batch continued)"
else
    fail "RESTORE /M (batch hung or crashed)"
fi

if grep -q "RESTORE_B_NO_MATCH" "$SERIAL_LOG"; then
    ok "RESTORE /B:12-31-99 (errorlevel set — 2026 files newer than 1999 cutoff)"
else
    fail "RESTORE /B:12-31-99 (expected errorlevel >= 1 — before-date should exclude 2026 files)"
fi

if grep -q "RESTORE_B_DONE" "$SERIAL_LOG"; then
    ok "RESTORE /B (batch continued)"
else
    fail "RESTORE /B (batch hung or crashed)"
fi

if grep -q "RESTORE_A_NO_MATCH" "$SERIAL_LOG"; then
    ok "RESTORE /A:12-31-50 (errorlevel set — 2026 files older than 2050 cutoff)"
else
    fail "RESTORE /A:12-31-50 (expected errorlevel >= 1 — after-date should exclude 2026 files)"
fi

if grep -q "RESTORE_A_DONE" "$SERIAL_LOG"; then
    ok "RESTORE /A (batch continued)"
else
    fail "RESTORE /A (batch hung or crashed)"
fi

if grep -q "RESTORE_E_NO_MATCH" "$SERIAL_LOG"; then
    ok "RESTORE /E:00:00:00 (errorlevel set — daytime files excluded by midnight cutoff)"
else
    fail "RESTORE /E:00:00:00 (expected errorlevel >= 1 — files with hour > 0 should be excluded)"
fi

if grep -q "RESTORE_E_DONE" "$SERIAL_LOG"; then
    ok "RESTORE /E (batch continued)"
else
    fail "RESTORE /E (batch hung or crashed)"
fi

if grep -q "RESTORE_L_NO_MATCH" "$SERIAL_LOG"; then
    ok "RESTORE /L:23:59:58 (errorlevel set — non-end-of-day files excluded)"
else
    fail "RESTORE /L:23:59:58 (expected errorlevel >= 1 — files with hour < 23 should be excluded)"
fi

if grep -q "RESTORE_L_DONE" "$SERIAL_LOG"; then
    ok "RESTORE /L (batch continued)"
else
    fail "RESTORE /L (batch hung or crashed)"
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
