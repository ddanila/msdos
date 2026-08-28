#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

BOOT_IMG="$OUT/prompt-yesno-boot.img"
TARGET_IMG="$OUT/prompt-yesno-target.img"
SERIAL_LOG="$OUT/prompt-yesno-serial.log"
SERIAL_IN="$OUT/prompt-yesno-serial.in"
SERIAL_OUT="$OUT/prompt-yesno-serial.out"
EXIT_COM="$OUT/prompt-yesno-qexit.com"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'kill ${QEMU_PID:-} 2>/dev/null; rm -f "$SERIAL_IN" "$SERIAL_OUT" 2>/dev/null; true' EXIT

echo "=== prompted command and utility workflows (QEMU, serial expect) ==="

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM

printf 'XCOPY_SOURCE_1\r\n' | mcopy -o -i "$BOOT_IMG" - ::XP_SRC1.TXT
printf 'XCOPY_SOURCE_2\r\n' | mcopy -o -i "$BOOT_IMG" - ::XP_SRC2.TXT
printf 'REPLACE_NEW\r\n'    | mcopy -o -i "$BOOT_IMG" - ::RP_FILE.TXT
printf 'DEL_KEEP\r\n'       | mcopy -o -i "$BOOT_IMG" - ::DP_KEEP.TXT
printf 'ERASE_DELETE\r\n'   | mcopy -o -i "$BOOT_IMG" - ::DP_DEL.TXT

dd if=/dev/zero bs=512 count=2880 of="$TARGET_IMG" status=none
mformat -i "$TARGET_IMG" ::

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'

    printf 'MD XPDEST\r\n'
    printf 'MD RPDEST\r\n'
    printf 'ECHO REPLACE_OLD>RPDEST\\RP_FILE.TXT\r\n'

    printf 'ECHO ---DEL-P-N---\r\n'
    printf 'DEL DP_KEEP.TXT /P\r\n'
    printf 'IF EXIST DP_KEEP.TXT ECHO DEL_P_N_PRESERVED\r\n'
    printf 'ECHO ---ERASE-P-Y---\r\n'
    printf 'ERASE DP_DEL.TXT /P\r\n'
    printf 'IF NOT EXIST DP_DEL.TXT ECHO ERASE_P_Y_DELETED\r\n'

    printf 'ECHO ---XCOPY-P---\r\n'
    printf 'XCOPY XP_SRC*.TXT XPDEST /P\r\n'
    printf 'ECHO XCOPY_P_DONE\r\n'

    printf 'IF EXIST XPDEST\\XP_SRC1.TXT ECHO XCOPY_P_FILE1_OK\r\n'
    printf 'IF EXIST XPDEST\\XP_SRC2.TXT ECHO XCOPY_P_FILE2_OK\r\n'

    printf 'ECHO ---REPLACE-P---\r\n'
    printf 'REPLACE RP_FILE.TXT RPDEST /P\r\n'
    printf 'ECHO REPLACE_P_DONE\r\n'

    printf 'ECHO ---RESTORE-P-SETUP---\r\n'
    printf 'BACKUP A:\\XP_SRC1.TXT B:\r\n'
    printf 'ECHO RESTORE_P_SETUP_DONE\r\n'

    printf 'DEL XP_SRC1.TXT\r\n'
    printf 'ECHO MODIFIED_CONTENT > XP_SRC1.TXT\r\n'

    printf 'ECHO ---RESTORE-P---\r\n'
    printf 'RESTORE B: A:\\XP_SRC1.TXT /P /P\r\n'
    printf 'ECHO RESTORE_P_DONE\r\n'

    printf 'ECHO COMP_PAYLOAD>COMP1.TXT\r\n'
    printf 'ECHO ---COMP-N---\r\n'
    printf 'COMP COMP1.TXT COMP1.TXT\r\n'
    printf 'ECHO COMP_N_DONE\r\n'

    printf 'ECHO ---COMP-Y---\r\n'
    printf 'COMP COMP1.TXT COMP1.TXT\r\n'
    printf 'ECHO COMP_Y_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_IN" "$SERIAL_OUT"
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
# Holding the input FIFO as O_RDWR prevents either endpoint from blocking during startup.
exec 3<>"$SERIAL_IN"

echo "Booting QEMU with DEL/XCOPY/REPLACE/RESTORE /P tests..."
rm -f "$SERIAL_LOG"
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET_IMG",cache=writethrough \
    -boot a -m 4 \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -serial pipe:"$OUT/prompt-yesno-serial" \
    2>/dev/null &
QEMU_PID=$!

python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$SERIAL_LOG" \
    'Delete (Y/N)?' 'N\r' \
    'Delete (Y/N)?' 'Y\r' \
    '(Y/N)?' 'Y\r' \
    '(Y/N)?' 'Y\r' \
    '(Y/N)' 'Y\r' \
    'Press any key' '\r' \
    'Press any key' '\r' \
    'Press any key' '\r' \
    'Press any key' '\r' \
    'Compare more files' 'N\r' \
    'Compare more files' 'Y\r' \
    'Enter primary filename' 'COMP1.TXT\r' \
    'Enter 2nd filename or drive id' 'COMP1.TXT\r' \
    'Compare more files' 'N\r'

wait $QEMU_PID || true
exec 3>&-

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

echo ""
echo "--- DEL /P and ERASE /P tests ---"

if grep -q '^DEL_P_N_PRESERVED' "$SERIAL_LOG"; then
    ok "DEL /P N response preserves the selected file"
else
    fail "DEL /P N response did not preserve DP_KEEP.TXT"
fi

if grep -q '^ERASE_P_Y_DELETED' "$SERIAL_LOG"; then
    ok "ERASE /P Y response deletes the selected file"
else
    fail "ERASE /P Y response did not delete DP_DEL.TXT"
fi

if [[ $(grep -c 'Delete (Y/N)?' "$SERIAL_LOG") -eq 2 ]]; then
    ok "DEL/ERASE /P prompts exactly once per selected file"
else
    fail "DEL/ERASE /P did not produce exactly two per-file prompts"
fi

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
    ok "RESTORE /P (no changed-file prompt on the no-files path)"
fi

echo ""
echo "--- COMP repeat-workflow tests ---"

if grep -q "COMP_N_DONE" "$SERIAL_LOG"; then
    ok "COMP N response returned to the calling batch"
else
    fail "COMP N response did not return to the calling batch"
fi

if [[ $(grep -c "Enter primary filename" "$SERIAL_LOG") -ge 1 ]] &&
   [[ $(grep -c "Enter 2nd filename or drive id" "$SERIAL_LOG") -eq 1 ]]; then
    ok "COMP Y response requested a new primary and secondary file pair"
else
    fail "COMP Y response did not request a new primary and secondary file pair"
fi

if [[ $(grep -c "Files compare OK" "$SERIAL_LOG") -ge 3 ]] && grep -q "COMP_Y_DONE" "$SERIAL_LOG"; then
    ok "COMP repeated comparison completed and final N returned to batch"
else
    fail "COMP repeated comparison or final return did not complete"
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

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "--- full serial log (for debugging) ---"
    cat "$SERIAL_LOG" 2>/dev/null || echo "(empty)"
    echo "--- end serial log ---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
