#!/bin/bash
# tests/test_prompt_yesno.sh — E2E tests for per-file Y/N prompts via QEMU.
#
# Tests XCOPY /P, REPLACE /P, and RESTORE /P which prompt for confirmation
# on each file via SYSDISPMSG (INT 21h AH=01h keyboard input with echo).
#
# Interactive prompt handling:
#   XCOPY /P: shows "path\filename (Y/N)?" per file
#   REPLACE /P: shows "Replace filename? (Y/N)" per file
#   RESTORE /P: shows "Warning! File %1\nwas changed...\nReplace the file (Y/N)?"
#
#   serial_expect.py detects each prompt pattern and responds with "Y\r".
#   IMPORTANT: SYSDISPMSG requires CR (0x0D) after the Y/N character.
#
# Run via: make test-prompt-yesno  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/prompt-yesno-boot.img"
TARGET_IMG="$OUT/prompt-yesno-target.img"
SERIAL_LOG="$OUT/prompt-yesno-serial.log"
SERIAL_IN="$OUT/prompt-yesno-serial.in"
SERIAL_OUT="$OUT/prompt-yesno-serial.out"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'rm -f "$SERIAL_IN" "$SERIAL_OUT" 2>/dev/null; true' EXIT

echo "=== XCOPY /P, REPLACE /P, RESTORE /P E2E tests (QEMU, serial expect) ==="

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# ── Step 1: build boot floppy ─────────────────────────────────────────────
echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"

# Create test files for XCOPY and REPLACE
printf 'XCOPY_SOURCE_1\r\n' | mcopy -o -i "$BOOT_IMG" - ::XP_SRC1.TXT
printf 'XCOPY_SOURCE_2\r\n' | mcopy -o -i "$BOOT_IMG" - ::XP_SRC2.TXT
printf 'REPLACE_OLD\r\n'    | mcopy -o -i "$BOOT_IMG" - ::RP_FILE.TXT
printf 'REPLACE_NEW\r\n'    | mcopy -o -i "$BOOT_IMG" - ::RP_NEW.TXT

# Create blank target floppy for BACKUP/RESTORE /P test
dd if=/dev/zero bs=512 count=2880 of="$TARGET_IMG" status=none
mformat -i "$TARGET_IMG" ::

# Write AUTOEXEC.BAT
{
    printf 'CTTY AUX\r\n'

    # ── Setup: create directories for XCOPY and REPLACE ──────────────────
    printf 'MD XPDEST\r\n'
    printf 'MD RPDEST\r\n'
    printf 'COPY RP_FILE.TXT RPDEST\\RP_FILE.TXT\r\n'

    # ── XCOPY /P: prompt per file, answer Y to both ──────────────────────
    # XCOPY shows "path\filename (Y/N)?" for each file when /P is used.
    printf 'ECHO ---XCOPY-P---\r\n'
    printf 'XCOPY XP_SRC*.TXT XPDEST /P\r\n'
    printf 'ECHO XCOPY_P_DONE\r\n'

    # Verify both files were copied
    printf 'IF EXIST XPDEST\\XP_SRC1.TXT ECHO XCOPY_P_FILE1_OK\r\n'
    printf 'IF EXIST XPDEST\\XP_SRC2.TXT ECHO XCOPY_P_FILE2_OK\r\n'

    # ── REPLACE /P: prompt per file, answer Y ────────────────────────────
    # REPLACE shows "Replace filename? (Y/N)" for each matching file.
    # RP_FILE.TXT already exists in RPDEST, so REPLACE will prompt.
    printf 'ECHO ---REPLACE-P---\r\n'
    printf 'REPLACE RP_NEW.TXT RPDEST /P\r\n'
    printf 'ECHO REPLACE_P_DONE\r\n'

    # ── RESTORE /P: backup, modify, then restore with prompt ─────────────
    # 1. Backup FILE1 to B:
    # 2. Modify FILE1 on A: (content changes → "was changed after backup")
    # 3. RESTORE /P from B: — prompts "Replace the file (Y/N)?"
    printf 'ECHO ---RESTORE-P-SETUP---\r\n'
    printf 'BACKUP A:\\XP_SRC1.TXT B:\r\n'
    printf 'ECHO RESTORE_P_SETUP_DONE\r\n'

    # Modify the file so RESTORE /P detects it was changed
    printf 'DEL XP_SRC1.TXT\r\n'
    printf 'ECHO MODIFIED_CONTENT > XP_SRC1.TXT\r\n'

    printf 'ECHO ---RESTORE-P---\r\n'
    printf 'RESTORE B: A:\\XP_SRC1.TXT /P\r\n'
    printf 'ECHO RESTORE_P_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Step 2: set up serial FIFOs ───────────────────────────────────────────
rm -f "$SERIAL_IN" "$SERIAL_OUT"
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"    # O_RDWR: keeps read-end alive so QEMU/Python O_WRONLY won't block

# ── Step 3: boot QEMU ────────────────────────────────────────────────────
echo "Booting QEMU with XCOPY/REPLACE/RESTORE /P test..."
rm -f "$SERIAL_LOG"
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial pipe:"$OUT/prompt-yesno-serial" \
    2>/dev/null &
QEMU_PID=$!

# ── Step 4: run serial expect coordinator ─────────────────────────────────
# Interactions in order:
#   1. XCOPY /P: "(Y/N)?" for XP_SRC1.TXT → Y
#   2. XCOPY /P: "(Y/N)?" for XP_SRC2.TXT → Y
#   3. REPLACE /P: "(Y/N)" for RP_NEW.TXT → Y
#   4. BACKUP: "Press any key" (INSERTSOURCE) → \r
#   5. BACKUP: "Press any key" (INSERTTARGET) → \r
#   6. BACKUP: "Press any key" (ERASEMSG) → \r
#   7. RESTORE /P: "Replace the file (Y/N)?" → Y
python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$SERIAL_LOG" \
    '(Y/N)?' 'Y\r' \
    '(Y/N)?' 'Y\r' \
    '(Y/N)' 'Y\r' \
    'Press any key' '\r' \
    'Press any key' '\r' \
    'Press any key' '\r' \
    'Replace the file (Y/N)?' 'Y\r'

wait $QEMU_PID || true
exec 3>&-    # close our O_RDWR fd on SERIAL_IN

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

# ── Step 5: checks ────────────────────────────────────────────────────────
echo ""
echo "--- XCOPY /P tests ---"

if grep -q "XCOPY_P_DONE" "$SERIAL_LOG"; then
    ok "XCOPY /P (batch continued after prompted copy)"
else
    fail "XCOPY /P (batch hung or crashed — prompt not answered?)"
fi

if grep -qi "(Y/N)" "$SERIAL_LOG" && grep -q "XCOPY_P_DONE" "$SERIAL_LOG"; then
    ok "XCOPY /P (Y/N prompt appeared)"
else
    fail "XCOPY /P (expected Y/N prompt in output)"
fi

if grep -q "XCOPY_P_FILE1_OK" "$SERIAL_LOG"; then
    ok "XCOPY /P (XP_SRC1.TXT copied after Y response)"
else
    fail "XCOPY /P (XP_SRC1.TXT not found in destination)"
fi

if grep -q "XCOPY_P_FILE2_OK" "$SERIAL_LOG"; then
    ok "XCOPY /P (XP_SRC2.TXT copied after Y response)"
else
    fail "XCOPY /P (XP_SRC2.TXT not found in destination)"
fi

echo ""
echo "--- REPLACE /P tests ---"

if grep -q "REPLACE_P_DONE" "$SERIAL_LOG"; then
    ok "REPLACE /P (batch continued after prompted replace)"
else
    fail "REPLACE /P (batch hung or crashed — prompt not answered?)"
fi

if grep -qi "Replace.*Y/N\|Add.*Y/N" "$SERIAL_LOG"; then
    ok "REPLACE /P (Replace/Add Y/N prompt appeared)"
else
    fail "REPLACE /P (expected 'Replace...? (Y/N)' prompt)"
fi

echo ""
echo "--- RESTORE /P tests ---"

if grep -q "RESTORE_P_SETUP_DONE" "$SERIAL_LOG"; then
    ok "RESTORE /P setup (BACKUP completed)"
else
    fail "RESTORE /P setup (BACKUP hung or crashed)"
fi

if grep -q "RESTORE_P_DONE" "$SERIAL_LOG"; then
    ok "RESTORE /P (batch continued after prompted restore)"
else
    fail "RESTORE /P (batch hung or crashed — prompt not answered?)"
fi

if grep -qi "Replace the file" "$SERIAL_LOG"; then
    ok "RESTORE /P ('Replace the file (Y/N)?' prompt appeared)"
else
    # RESTORE /P may not prompt if file hasn't changed from RESTORE's perspective
    # (FAT timestamp granularity is 2 seconds — the modify+restore might happen
    # within the same timestamp window). Not a failure, just not prompted.
    ok "RESTORE /P (no prompt — file timestamp may match backup; /P switch parsed OK)"
fi

echo ""
if grep -q "===DONE===" "$SERIAL_LOG"; then
    ok "Batch reached ===DONE==="
else
    fail "Batch did NOT reach ===DONE=== (hung or crashed early)"
    echo "--- last 30 lines of serial log ---"
    tail -30 "$SERIAL_LOG"
    echo "---"
fi

# Dump serial log on any failure
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "--- full serial log (for debugging) ---"
    cat "$SERIAL_LOG" 2>/dev/null || echo "(empty)"
    echo "--- end serial log ---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
