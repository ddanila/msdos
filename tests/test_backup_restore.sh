#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

BOOT_IMG="$OUT/floppy-backup-boot.img"
TARGET_IMG="$OUT/floppy-backup-target.img"
SERIAL_LOG="$OUT/backup-serial.log"
EXIT_COM="$OUT/qemu-exit.com"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== BACKUP / RESTORE E2E tests (QEMU) ==="

echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

printf 'BACKUP_FILE_ONE\r\n\x1a' | mcopy -o -i "$BOOT_IMG" - ::BAKF1.TXT
printf 'BACKUP_FILE_TWO\r\n\x1a' | mcopy -o -i "$BOOT_IMG" - ::BAKF2.TXT
printf 'DEEP_FILE\r\n\x1a'       | mcopy -o -i "$BOOT_IMG" - ::BAKDEEP.TXT
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'

    printf 'MD BAKSRC\r\n'
    printf 'COPY BAKF1.TXT BAKSRC\\FILE1.TXT\r\n'
    printf 'COPY BAKF2.TXT BAKSRC\\FILE2.TXT\r\n'

    printf 'ECHO ---FC-SANITY---\r\n'
    printf 'FC /B BAKF1.TXT BAKF1.TXT\r\n'
    printf 'ECHO FC_SANITY_DONE\r\n'

    printf 'BACKUP A:BAKSRC\\*.TXT B: /D:01-01-90 /D:01-01-90\r\n'
    printf 'IF ERRORLEVEL 1 ECHO BACKUP_DUP_D_REJECTED\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /T:00:00:00 /T:00:00:00\r\n'
    printf 'IF ERRORLEVEL 1 ECHO BACKUP_DUP_T_REJECTED\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /Z\r\n'
    printf 'IF ERRORLEVEL 1 ECHO BACKUP_UNKNOWN_REJECTED\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: EXTRA\r\n'
    printf 'IF ERRORLEVEL 1 ECHO BACKUP_ARITY_REJECTED\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /D:02-30-90\r\n'
    printf 'IF ERRORLEVEL 1 ECHO BACKUP_DATE_REJECTED\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /T:24:00:00\r\n'
    printf 'IF ERRORLEVEL 1 ECHO BACKUP_TIME_REJECTED\r\n'

    printf 'RESTORE B: A:BAKSRC\\*.TXT /Z\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_UNKNOWN_REJECTED\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT EXTRA\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_ARITY_REJECTED\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /B:02-30-90\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_DATE_REJECTED\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /E:24:00:00\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_TIME_REJECTED\r\n'
    printf 'RESTORE A: A:BAKSRC\\*.TXT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_SAME_DRIVE_REJECTED\r\n'

    printf 'ECHO ---BACKUP-BASIC---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B:\r\n'
    printf 'ECHO BACKUP_BASIC_DONE\r\n'

    printf 'ECHO ---BACKUP-S---\r\n'
    printf 'MD BAKSRC\\SUB\r\n'
    printf 'COPY BAKDEEP.TXT BAKSRC\\SUB\\DEEP.TXT\r\n'
    printf 'BACKUP A:BAKSRC B: /S /S\r\n'
    printf 'ECHO BACKUP_S_DONE\r\n'

    printf 'ECHO ---BACKUP-M---\r\n'
    printf 'ATTRIB -A BAKSRC\\FILE1.TXT\r\n'
    printf 'ATTRIB -A BAKSRC\\FILE2.TXT\r\n'
    printf 'ATTRIB +A BAKSRC\\FILE2.TXT\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /M /M\r\n'
    printf 'DEL BAKSRC\\FILE1.TXT\r\n'
    printf 'DEL BAKSRC\\FILE2.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT\r\n'
    printf 'IF EXIST BAKSRC\\FILE2.TXT ECHO BACKUP_M_FILE2_IN_BACKUP\r\n'
    printf 'FC /B BAKSRC\\FILE2.TXT BAKF2.TXT >NUL\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO BACKUP_M_FILE2_CONTENT_OK\r\n'
    printf 'IF NOT EXIST BAKSRC\\FILE1.TXT ECHO BACKUP_M_FILE1_EXCLUDED\r\n'
    printf 'ECHO BACKUP_M_DONE\r\n'
    printf 'COPY BAKF1.TXT BAKSRC\\FILE1.TXT\r\n'

    printf 'ECHO ---BACKUP-A---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B:\r\n'
    printf 'COPY BAKF1.TXT BAKSRC\\EXTRA.TXT\r\n'
    printf 'BACKUP A:BAKSRC\\EXTRA.TXT B: /A /A\r\n'
    printf 'DEL BAKSRC\\FILE1.TXT\r\n'
    printf 'DEL BAKSRC\\FILE2.TXT\r\n'
    printf 'DEL BAKSRC\\EXTRA.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT\r\n'
    printf 'IF EXIST BAKSRC\\FILE1.TXT ECHO BACKUP_A_FILE1_PRESERVED\r\n'
    printf 'IF EXIST BAKSRC\\FILE2.TXT ECHO BACKUP_A_FILE2_PRESERVED\r\n'
    printf 'IF EXIST BAKSRC\\EXTRA.TXT ECHO BACKUP_A_EXTRA_ADDED\r\n'
    printf 'FC /B BAKSRC\\FILE1.TXT BAKF1.TXT >NUL\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO BACKUP_A_FILE1_CONTENT_OK\r\n'
    printf 'FC /B BAKSRC\\FILE2.TXT BAKF2.TXT >NUL\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO BACKUP_A_FILE2_CONTENT_OK\r\n'
    printf 'FC /B BAKSRC\\EXTRA.TXT BAKF1.TXT >NUL\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO BACKUP_A_EXTRA_CONTENT_OK\r\n'
    printf 'ECHO BACKUP_A_DONE\r\n'
    printf 'DEL BAKSRC\\EXTRA.TXT\r\n'

    printf 'ECHO ---BACKUP-NOFILES---\r\n'
    printf 'BACKUP A:BAKSRC\\*.XYZ B:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO BACKUP_NOFIL_ERRORLEVEL\r\n'
    printf 'ECHO BACKUP_NOFIL_DONE\r\n'

    printf 'ECHO ---BACKUP-F---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /F /F\r\n'
    printf 'ECHO BACKUP_F_DONE\r\n'

    printf 'ECHO ---RESTORE-BASIC---\r\n'
    printf 'BACKUP A:BAKSRC\\FILE1.TXT B:\r\n'
    printf 'DEL BAKSRC\\FILE1.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\FILE1.TXT\r\n'
    printf 'IF EXIST BAKSRC\\FILE1.TXT ECHO RESTORE_BASIC_OK\r\n'
    printf 'FC /B BAKSRC\\FILE1.TXT BAKF1.TXT >NUL\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO RESTORE_BASIC_CONTENT_OK\r\n'
    printf 'ECHO RESTORE_BASIC_DONE\r\n'

    printf 'ECHO ---RESTORE-S---\r\n'
    printf 'BACKUP A:BAKSRC B: /S\r\n'
    printf 'DEL BAKSRC\\SUB\\DEEP.TXT\r\n'
    printf 'RD BAKSRC\\SUB\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.* /S /S\r\n'
    printf 'IF EXIST BAKSRC\\SUB\\DEEP.TXT ECHO RESTORE_S_OK\r\n'
    printf 'FC /B BAKSRC\\SUB\\DEEP.TXT BAKDEEP.TXT >NUL\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO RESTORE_S_CONTENT_OK\r\n'
    printf 'ECHO RESTORE_S_DONE\r\n'

    printf 'ECHO ---RESTORE-N---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B:\r\n'
    printf 'DEL BAKSRC\\FILE2.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /N /N\r\n'
    printf 'IF EXIST BAKSRC\\FILE2.TXT ECHO RESTORE_N_OK\r\n'
    printf 'FC /B BAKSRC\\FILE2.TXT BAKF2.TXT >NUL\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO RESTORE_N_CONTENT_OK\r\n'
    printf 'ECHO RESTORE_N_DONE\r\n'

    printf 'ECHO ---BACKUP-D---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /D:01-01-80\r\n'
    printf 'DEL BAKSRC\\FILE1.TXT\r\n'
    printf 'DEL BAKSRC\\FILE2.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT\r\n'
    printf 'IF EXIST BAKSRC\\FILE1.TXT ECHO BACKUP_D_FILE1_OK\r\n'
    printf 'IF EXIST BAKSRC\\FILE2.TXT ECHO BACKUP_D_FILE2_OK\r\n'
    printf 'ECHO BACKUP_D_DONE\r\n'

    printf 'ECHO ---BACKUP-T---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /T:00:00:00\r\n'
    printf 'DEL BAKSRC\\FILE1.TXT\r\n'
    printf 'DEL BAKSRC\\FILE2.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT\r\n'
    printf 'IF EXIST BAKSRC\\FILE1.TXT ECHO BACKUP_T_FILE1_OK\r\n'
    printf 'IF EXIST BAKSRC\\FILE2.TXT ECHO BACKUP_T_FILE2_OK\r\n'
    printf 'ECHO BACKUP_T_DONE\r\n'

    printf 'ECHO ---BACKUP-L---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B: /L /L\r\n'
    printf 'IF EXIST A:\\BACKUP.LOG ECHO BACKUP_L_LOG_EXISTS\r\n'
    printf 'ECHO BACKUP_L_DONE\r\n'

    printf 'ECHO ---RESTORE-M---\r\n'
    printf 'BACKUP A:BAKSRC\\*.TXT B:\r\n'
    printf 'ATTRIB -A BAKSRC\\FILE1.TXT\r\n'
    printf 'ATTRIB -A BAKSRC\\FILE2.TXT\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /M\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_M_NO_MATCH\r\n'
    printf 'ECHO RESTORE_M_DONE\r\n'

    printf 'ECHO ---RESTORE-B---\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /B:12-31-99\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_B_NO_MATCH\r\n'
    printf 'ECHO RESTORE_B_DONE\r\n'

    printf 'ECHO ---RESTORE-A---\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /A:12-31-99\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO RESTORE_A_MATCH\r\n'
    printf 'ECHO RESTORE_A_DONE\r\n'

    printf 'ECHO ---RESTORE-E---\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /E:00:00:00\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_E_NO_MATCH\r\n'
    printf 'ECHO RESTORE_E_DONE\r\n'

    printf 'ECHO ---RESTORE-L---\r\n'
    printf 'RESTORE B: A:BAKSRC\\*.TXT /L:23:59:58\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_L_NO_MATCH\r\n'
    printf 'ECHO RESTORE_L_DONE\r\n'

    printf 'DEL BAKSRC\\FILE1.TXT\r\n'
    printf 'DEL BAKSRC\\FILE2.TXT\r\n'
    printf 'DEL BAKSRC\\SUB\\DEEP.TXT\r\n'
    printf 'RD BAKSRC\\SUB\r\n'
    printf 'RD BAKSRC\r\n'

    printf 'ECHO ===DONE===\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

dd if=/dev/zero bs=512 count=2880 of="$TARGET_IMG" status=none
mformat -i "$TARGET_IMG" -f 1440 ::

echo "Booting QEMU with A:=boot B:=blank target (may take ~90s)..."
rm -f "$SERIAL_LOG"
(while true; do sleep 0.2; printf '\r\n'; done) | \
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi


echo ""
echo "--- BACKUP tests ---"

backup_parser_ok=true
for marker in D T; do
    grep -q "^BACKUP_DUP_${marker}_REJECTED" "$SERIAL_LOG" || backup_parser_ok=false
done
for marker in UNKNOWN ARITY DATE TIME; do
    grep -q "^BACKUP_${marker}_REJECTED" "$SERIAL_LOG" || backup_parser_ok=false
done
if $backup_parser_ok \
    && grep -q 'Invalid date - /D:01-01-90' "$SERIAL_LOG" \
    && grep -q 'Invalid time - /T:00:00:00' "$SERIAL_LOG" \
    && grep -q 'Invalid switch - /Z' "$SERIAL_LOG" \
    && grep -q 'Too many parameters - EXTRA' "$SERIAL_LOG"; then
    ok "BACKUP rejects duplicate valued switches and malformed command classes"
else
    fail "BACKUP parser rejection matrix was incomplete"
fi

restore_parser_ok=true
for marker in UNKNOWN ARITY DATE TIME SAME_DRIVE; do
    grep -q "^RESTORE_${marker}_REJECTED" "$SERIAL_LOG" || restore_parser_ok=false
done
if $restore_parser_ok \
    && [[ $(grep -c 'Invalid switch - /Z' "$SERIAL_LOG") -ge 2 ]] \
    && [[ $(grep -c 'Too many parameters - EXTRA' "$SERIAL_LOG") -ge 2 ]] \
    && grep -q 'Invalid date - /B:02-30-90' "$SERIAL_LOG" \
    && grep -q 'Invalid time - /E:24:00:00' "$SERIAL_LOG" \
    && grep -q 'Source and target drives are the same' "$SERIAL_LOG"; then
    ok "RESTORE rejects every malformed command class with exact diagnostics"
else
    fail "RESTORE parser rejection matrix was incomplete"
fi

if sed -n '/---FC-SANITY---/,/FC_SANITY_DONE/p' "$SERIAL_LOG" \
    | grep -qi 'no differences'; then
    ok "FC /B independently confirmed identical binary payloads"
else
    fail "FC /B did not execute its identical-file comparison contract"
fi

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

if grep -q "BACKUP_M_FILE2_CONTENT_OK" "$SERIAL_LOG"; then
    ok "BACKUP /M restored FILE2 with exact binary contents"
else
    fail "BACKUP /M restored FILE2 contents differ"
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

for marker in FILE1 FILE2 EXTRA; do
    if grep -q "BACKUP_A_${marker}_CONTENT_OK" "$SERIAL_LOG"; then
        ok "BACKUP /A preserved exact $marker contents"
    else
        fail "BACKUP /A $marker contents differ after restore"
    fi
done

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

if grep -q "BACKUP_F_DONE" "$SERIAL_LOG"; then
    ok "BACKUP /F (format switch parsed, batch continued with pre-formatted disk)"
else
    fail "BACKUP /F (batch hung or crashed — /F parsing may have failed)"
fi

echo ""
echo "--- RESTORE tests ---"

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

if grep -q "RESTORE_BASIC_CONTENT_OK" "$SERIAL_LOG"; then
    ok "RESTORE basic reproduced exact binary contents"
else
    fail "RESTORE basic contents differ"
fi

if grep -q "RESTORE_S_OK" "$SERIAL_LOG"; then
    ok "RESTORE /S (DEEP.TXT restored in subdir)"
else
    fail "RESTORE /S (expected BAKSRC\\SUB\\DEEP.TXT to be restored)"
fi

if grep -q "RESTORE_S_CONTENT_OK" "$SERIAL_LOG"; then
    ok "RESTORE /S reproduced exact nested-file contents"
else
    fail "RESTORE /S nested-file contents differ"
fi

if grep -q "RESTORE_N_OK" "$SERIAL_LOG"; then
    ok "RESTORE /N (restored only missing FILE2)"
else
    fail "RESTORE /N (expected FILE2 to be restored)"
fi

if grep -q "RESTORE_N_CONTENT_OK" "$SERIAL_LOG"; then
    ok "RESTORE /N reproduced exact missing-file contents"
else
    fail "RESTORE /N missing-file contents differ"
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

if grep -q "RESTORE_A_MATCH" "$SERIAL_LOG"; then
    ok "RESTORE /A:12-31-99 includes the newer 2026 backup entries"
else
    fail "RESTORE /A:12-31-99 after-date inclusion contract"
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
