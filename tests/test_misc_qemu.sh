#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

BOOT_IMG="$OUT/floppy-misc-qemu.img"
SERIAL_LOG="$OUT/misc-qemu-serial.log"
EXIT_COM="$OUT/misc-qemu-exit.com"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

SRC="$REPO_ROOT/src/v4.0/src"

echo "=== CHKDSK / MODE CON / IFSFUNC / FILESYS / FASTOPEN / GRAPHICS / PRINT / KEYB E2E tests (QEMU) ==="

echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
printf '@ECHO OFF\r\nECHO Hello World | FIND "Hello"\r\n' \
    | mcopy -o -i "$BOOT_IMG" - ::FINDPIPE.BAT


{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'

    printf 'ECHO ---CHKDSK---\r\n'
    printf 'CHKDSK\r\n'
    printf 'ECHO CHKDSK_DONE\r\n'

    printf 'ECHO ---CHKDSK-V---\r\n'
    printf 'CHKDSK /V\r\n'
    printf 'ECHO CHKDSK_V_DONE\r\n'

    printf 'ECHO ---MODE-CON---\r\n'
    printf 'MODE CON /STATUS\r\n'
    printf 'ECHO MODE_CON_DONE\r\n'

    printf 'ECHO ---MODE-STA---\r\n'
    printf 'MODE CON /STA\r\n'
    printf 'ECHO MODE_STA_DONE\r\n'
    printf 'ECHO ---MODE-STAT---\r\n'
    printf 'MODE CON /STAT\r\n'
    printf 'ECHO MODE_STAT_DONE\r\n'

    printf 'ECHO ---MODE-CON-SET---\r\n'
    printf 'MODE CON COLS=80 LINES=25\r\n'
    printf 'ECHO MODE_CON_SET_DONE\r\n'

    printf 'ECHO ---MODE-TYPAMAT---\r\n'
    printf 'MODE CON RATE=30 DELAY=1\r\n'
    printf 'ECHO MODE_TYPAMAT_DONE\r\n'

    printf 'ECHO ---CHKDSK-FILE---\r\n'
    printf 'CHKDSK A:\COMMAND.COM\r\n'
    printf 'ECHO CHKDSK_FILE_DONE\r\n'

    printf 'ECHO ---IFSFUNC---\r\n'
    printf 'IFSFUNC\r\n'
    printf 'ECHO IFSFUNC_DONE\r\n'

    printf 'ECHO ---IFSFUNC-AGAIN---\r\n'
    printf 'IFSFUNC\r\n'
    printf 'ECHO IFSFUNC_AGAIN_DONE\r\n'

    printf 'ECHO ---FILESYS---\r\n'
    printf 'FILESYS\r\n'
    printf 'ECHO FILESYS_DONE\r\n'

    printf 'ECHO ---FASTOPEN---\r\n'
    printf 'FASTOPEN C:=50\r\n'
    printf 'ECHO FASTOPEN_DONE\r\n'

    printf 'ECHO ---FASTOPEN-AGAIN---\r\n'
    printf 'FASTOPEN C:=50\r\n'
    printf 'ECHO FASTOPEN_AGAIN_DONE\r\n'

    printf 'ECHO ---FASTOPEN-X---\r\n'
    printf 'FASTOPEN D:=20 /X\r\n'
    printf 'ECHO FASTOPEN_X_DONE\r\n'

    printf 'ECHO ---GRAPHICS---\r\n'
    printf 'GRAPHICS\r\n'
    printf 'ECHO GRAPHICS_DONE\r\n'

    printf 'ECHO ---GRAPHICS-AGAIN---\r\n'
    printf 'GRAPHICS\r\n'
    printf 'ECHO GRAPHICS_AGAIN_DONE\r\n'

    printf 'ECHO ---PRINT---\r\n'
    printf 'PRINT /D:PRN /B:512 /Q:5 /S:8 /U:1 /M:2\r\n'
    printf 'ECHO PRINT_DONE\r\n'

    printf 'ECHO ---PRINT-AGAIN---\r\n'
    printf 'PRINT\r\n'
    printf 'ECHO PRINT_AGAIN_DONE\r\n'

    printf 'ECHO ---PRINT-P---\r\n'
    printf 'PRINT AUTOEXEC.BAT /P\r\n'
    printf 'ECHO PRINT_P_DONE\r\n'

    printf 'ECHO ---PRINT-C---\r\n'
    printf 'PRINT AUTOEXEC.BAT /C\r\n'
    printf 'ECHO PRINT_C_DONE\r\n'

    printf 'ECHO ---PRINT-T---\r\n'
    printf 'PRINT /T\r\n'
    printf 'ECHO PRINT_T_DONE\r\n'

    printf 'ECHO ---KEYB---\r\n'
    printf 'KEYB US\r\n'
    printf 'ECHO KEYB_DONE\r\n'

    printf 'ECHO ---KEYB-STATUS---\r\n'
    printf 'KEYB\r\n'
    printf 'ECHO KEYB_STATUS_DONE\r\n'

    printf 'ECHO ---KEYB-GR---\r\n'
    printf 'KEYB GR,,KEYBOARD.SYS\r\n'
    printf 'ECHO KEYB_GR_DONE\r\n'

    printf 'ECHO ---KEYB-GR-STATUS---\r\n'
    printf 'KEYB\r\n'
    printf 'ECHO KEYB_GR_STATUS_DONE\r\n'

    printf 'ECHO ---KEYB-UK-850---\r\n'
    printf 'KEYB UK,850,KEYBOARD.SYS\r\n'
    printf 'ECHO KEYB_UK_850_DONE\r\n'

    printf 'ECHO ---KEYB-UK-STATUS---\r\n'
    printf 'KEYB\r\n'
    printf 'ECHO KEYB_UK_STATUS_DONE\r\n'

    printf 'ECHO ---KEYB-ID---\r\n'
    printf 'KEYB FR,850,KEYBOARD.SYS /ID:189\r\n'
    printf 'ECHO KEYB_ID_DONE\r\n'

    printf 'ECHO ---KEYB-FR-STATUS---\r\n'
    printf 'KEYB\r\n'
    printf 'ECHO KEYB_FR_STATUS_DONE\r\n'

    printf 'ECHO ---GRAPHICS-R---\r\n'
    printf 'GRAPHICS /R\r\n'
    printf 'ECHO GRAPHICS_R_DONE\r\n'

    printf 'ECHO ---GRAPHICS-B---\r\n'
    printf 'GRAPHICS /B\r\n'
    printf 'ECHO GRAPHICS_B_DONE\r\n'

    printf 'ECHO ---GRAPHICS-LCD---\r\n'
    printf 'GRAPHICS /LCD\r\n'
    printf 'ECHO GRAPHICS_LCD_DONE\r\n'

    printf 'ECHO ---GRAPHICS-PB---\r\n'
    printf 'GRAPHICS /PB:STD\r\n'
    printf 'ECHO GRAPHICS_PB_DONE\r\n'

    printf 'ECHO ---GRAPHICS-PRINTBOX---\r\n'
    printf 'GRAPHICS /PRINTBOX:STD\r\n'
    printf 'ECHO GRAPHICS_PRINTBOX_DONE\r\n'

    printf 'ECHO ---MODE-COM---\r\n'
    printf 'MODE COM1: 9600,N,8,1\r\n'
    printf 'ECHO MODE_COM_DONE\r\n'

    printf 'ECHO ---MODE-LPT---\r\n'
    printf 'MODE LPT1: 80,6\r\n'
    printf 'ECHO MODE_LPT_DONE\r\n'

    printf 'ECHO ---MODE-REDIRECT---\r\n'
    printf 'MODE LPT1:=COM1:\r\n'
    printf 'ECHO MODE_REDIRECT_DONE\r\n'

    printf 'ECHO ---COMMAND-HELP---\r\n'
    printf 'COMMAND /?\r\n'
    printf 'ECHO COMMAND_HELP_DONE\r\n'

    printf 'ECHO banana>SORTIN.TXT\r\n'
    printf 'ECHO apple>>SORTIN.TXT\r\n'
    printf 'ECHO cherry>>SORTIN.TXT\r\n'
    printf 'ECHO ---SORT-FILE---\r\n'
    printf 'SORT <SORTIN.TXT\r\n'
    printf 'ECHO SORT_FILE_DONE\r\n'
    printf 'MD TREEFIX\r\n'
    printf 'MD TREEFIX\\BRANCH\r\n'
    printf 'ECHO LEAF>TREEFIX\\BRANCH\\LEAF.TXT\r\n'
    printf 'ECHO ---TREE-FILES---\r\n'
    printf 'TREE TREEFIX /F /A\r\n'
    printf 'ECHO TREE_FILES_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'

    printf 'ECHO ---FIND-STDIN---\r\n'
    printf 'COMMAND /C FINDPIPE.BAT\r\n'

    printf 'ECHO ---DIR-P---\r\n'
    printf 'DIR /P\r\n'
    printf 'ECHO DIR_P_DONE\r\n'
    printf 'QEXIT.COM\r\n'

} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

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

echo ""
echo "--- CHKDSK tests ---"

if grep -qi "bytes total disk space" "$SERIAL_LOG"; then
    ok "CHKDSK (disk stats: total disk space reported)"
else
    fail "CHKDSK (expected 'bytes total disk space' in output)"
fi

if grep -qi "bytes available on disk" "$SERIAL_LOG"; then
    ok "CHKDSK (disk stats: available space reported)"
else
    fail "CHKDSK (expected 'bytes available on disk' in output)"
fi

if grep -q "CHKDSK_DONE" "$SERIAL_LOG"; then
    ok "CHKDSK (batch continued after run)"
else
    fail "CHKDSK (batch hung or crashed)"
fi

if grep -qi "COMMAND" "$SERIAL_LOG" && grep -q "CHKDSK_V_DONE" "$SERIAL_LOG"; then
    ok "CHKDSK /V (verbose file listing includes COMMAND.COM)"
else
    fail "CHKDSK /V (expected file listing with 'COMMAND' and CHKDSK_V_DONE marker)"
fi

if grep -q "CHKDSK_FILE_DONE" "$SERIAL_LOG"; then
    ok "CHKDSK A:\\COMMAND.COM (file allocation check, batch continued)"
else
    fail "CHKDSK A:\\COMMAND.COM (batch hung or crashed)"
fi

echo ""
echo "--- MODE CON tests ---"

if grep -qi "Status" "$SERIAL_LOG" && grep -q "MODE_CON_DONE" "$SERIAL_LOG"; then
    ok "MODE CON /STATUS (status output printed, batch continued)"
else
    fail "MODE CON /STATUS (expected 'Status' output and MODE_CON_DONE marker)"
fi

mode_sta_section=$(sed -n '/---MODE-STA---/,/MODE_STA_DONE/p' "$SERIAL_LOG")
if echo "$mode_sta_section" | grep -qi "Status"; then
    ok "MODE CON /STA (short synonym reports console status)"
else
    fail "MODE CON /STA (expected console status output)"
fi
mode_stat_section=$(sed -n '/---MODE-STAT---/,/MODE_STAT_DONE/p' "$SERIAL_LOG")
if echo "$mode_stat_section" | grep -qi "Status"; then
    ok "MODE CON /STAT (short synonym reports console status)"
else
    fail "MODE CON /STAT (expected console status output)"
fi

if grep -q "MODE_CON_SET_DONE" "$SERIAL_LOG"; then
    ok "MODE CON COLS=80 LINES=25 (set console dimensions, batch continued)"
else
    fail "MODE CON COLS=80 LINES=25 (batch hung or crashed)"
fi

if grep -q "MODE_TYPAMAT_DONE" "$SERIAL_LOG"; then
    ok "MODE CON RATE=30 DELAY=1 (set typematic rate, batch continued)"
else
    fail "MODE CON RATE=30 DELAY=1 (batch hung or crashed)"
fi

echo ""
echo "--- IFSFUNC tests ---"

if grep -q "IFSFUNC_DONE" "$SERIAL_LOG"; then
    ok "IFSFUNC (first call installed silently, batch continued)"
else
    fail "IFSFUNC (batch hung or crashed after first call)"
fi

if grep -qi "IFSFUNC already installed" "$SERIAL_LOG"; then
    ok "IFSFUNC (second call: 'IFSFUNC already installed' message)"
else
    fail "IFSFUNC (expected 'IFSFUNC already installed' on second call)"
fi

if grep -q "IFSFUNC_AGAIN_DONE" "$SERIAL_LOG"; then
    ok "IFSFUNC (second call: batch continued)"
else
    fail "IFSFUNC (batch hung or crashed after second call)"
fi

echo ""
echo "--- FILESYS tests ---"

if grep -q "FILESYS_DONE" "$SERIAL_LOG"; then
    ok "FILESYS (installed silently, batch continued)"
else
    fail "FILESYS (batch hung or crashed)"
fi

echo ""
echo "--- FASTOPEN tests ---"

if grep -q "FASTOPEN_DONE" "$SERIAL_LOG"; then
    ok "FASTOPEN C:=50 (first call installed silently, batch continued)"
else
    fail "FASTOPEN C:=50 (batch hung or crashed after first call)"
fi

if grep -q "FASTOPEN_AGAIN_DONE" "$SERIAL_LOG"; then
    ok "FASTOPEN C:=50 (second call: batch continued without hang)"
else
    fail "FASTOPEN C:=50 (batch hung or crashed after second call)"
fi

if grep -q "FASTOPEN_X_DONE" "$SERIAL_LOG"; then
    ok "FASTOPEN D:=20 /X (expanded memory switch parsed, batch continued)"
else
    fail "FASTOPEN D:=20 /X (batch hung or crashed — /X parsing may have failed)"
fi

echo ""
echo "--- GRAPHICS tests ---"

if grep -q "GRAPHICS_DONE" "$SERIAL_LOG"; then
    ok "GRAPHICS (first call loaded GRAPHICS.PRO, batch continued)"
else
    fail "GRAPHICS (batch hung or crashed after first call)"
fi

if grep -q "GRAPHICS_AGAIN_DONE" "$SERIAL_LOG"; then
    ok "GRAPHICS (second call reloaded silently, batch continued)"
else
    fail "GRAPHICS (batch hung or crashed after second call)"
fi

echo ""
echo "--- PRINT tests ---"

if grep -qi "Resident part of PRINT installed" "$SERIAL_LOG"; then
    ok "PRINT /D:PRN (printed 'Resident part of PRINT installed')"
else
    fail "PRINT /D:PRN (expected 'Resident part of PRINT installed')"
fi

if grep -q "PRINT_DONE" "$SERIAL_LOG"; then
    ok "PRINT /D:PRN /B:512 /Q:5 /S:8 /U:1 /M:2 (batch continued after install with params)"
else
    fail "PRINT /D:PRN /B:512 /Q:5 /S:8 /U:1 /M:2 (batch hung or crashed)"
fi

if grep -q "PRINT_AGAIN_DONE" "$SERIAL_LOG"; then
    ok "PRINT (second call: batch continued)"
else
    fail "PRINT (batch hung or crashed on second call)"
fi

if grep -q "PRINT_P_DONE" "$SERIAL_LOG"; then
    ok "PRINT AUTOEXEC.BAT /P (add to queue, batch continued)"
else
    fail "PRINT AUTOEXEC.BAT /P (batch hung or crashed)"
fi

if grep -q "PRINT_C_DONE" "$SERIAL_LOG"; then
    ok "PRINT AUTOEXEC.BAT /C (remove from queue, batch continued)"
else
    fail "PRINT AUTOEXEC.BAT /C (batch hung or crashed)"
fi

if grep -q "PRINT_T_DONE" "$SERIAL_LOG"; then
    ok "PRINT /T (terminate queue, batch continued)"
else
    fail "PRINT /T (batch hung or crashed)"
fi

echo ""
echo "--- KEYB tests ---"

if grep -q "KEYB_DONE" "$SERIAL_LOG"; then
    ok "KEYB US (loaded US layout, batch continued)"
else
    fail "KEYB US (batch hung or crashed — KEYBOARD.SYS missing or load failed)"
fi

if grep -qi "Current keyboard code" "$SERIAL_LOG"; then
    ok "KEYB (no args: 'Current keyboard code' shown)"
else
    fail "KEYB (no args: expected 'Current keyboard code' output)"
fi

if grep -q "KEYB_STATUS_DONE" "$SERIAL_LOG"; then
    ok "KEYB (no args: batch continued)"
else
    fail "KEYB (batch hung or crashed after status query)"
fi

if grep -q "KEYB_GR_DONE" "$SERIAL_LOG"; then
    ok "KEYB GR,,KEYBOARD.SYS (loaded German layout, batch continued)"
else
    fail "KEYB GR,,KEYBOARD.SYS (batch hung or crashed)"
fi

if grep -qi "Current keyboard code.*GR\|code.*GR" "$SERIAL_LOG" && grep -q "KEYB_GR_STATUS_DONE" "$SERIAL_LOG"; then
    ok "KEYB (no args after GR: shows 'GR' as current layout)"
else
    fail "KEYB (no args after GR: expected 'Current keyboard code' with 'GR')"
fi

if grep -q "KEYB_UK_850_DONE" "$SERIAL_LOG"; then
    ok "KEYB UK,850,KEYBOARD.SYS (loaded UK layout with code page, batch continued)"
else
    fail "KEYB UK,850,KEYBOARD.SYS (batch hung or crashed)"
fi

if grep -qi "Current keyboard code.*UK\|code.*UK" "$SERIAL_LOG" && grep -q "KEYB_UK_STATUS_DONE" "$SERIAL_LOG"; then
    ok "KEYB (no args after UK,850: shows 'UK' as current layout)"
else
    fail "KEYB (no args after UK,850: expected 'Current keyboard code' with 'UK')"
fi

if grep -q "KEYB_ID_DONE" "$SERIAL_LOG"; then
    ok "KEYB FR,850,KEYBOARD.SYS /ID:189 (loaded French layout with /ID, batch continued)"
else
    fail "KEYB FR,850,KEYBOARD.SYS /ID:189 (batch hung or crashed)"
fi

if grep -qi "Current keyboard code.*FR\|code.*FR" "$SERIAL_LOG" && grep -q "KEYB_FR_STATUS_DONE" "$SERIAL_LOG"; then
    ok "KEYB (no args after FR /ID:189: shows 'FR' as current layout)"
else
    fail "KEYB (no args after FR /ID:189: expected 'Current keyboard code' with 'FR')"
fi

echo ""
echo "--- GRAPHICS /R /B tests ---"

if grep -q "GRAPHICS_R_DONE" "$SERIAL_LOG"; then
    ok "GRAPHICS /R (loaded with reverse printing, batch continued)"
else
    fail "GRAPHICS /R (batch hung or crashed)"
fi

if grep -q "GRAPHICS_B_DONE" "$SERIAL_LOG"; then
    ok "GRAPHICS /B (loaded with background printing, batch continued)"
else
    fail "GRAPHICS /B (batch hung or crashed)"
fi

if grep -q "GRAPHICS_LCD_DONE" "$SERIAL_LOG"; then
    ok "GRAPHICS /LCD (loaded with LCD aspect ratio, batch continued)"
else
    fail "GRAPHICS /LCD (batch hung or crashed)"
fi

if grep -q "GRAPHICS_PB_DONE" "$SERIAL_LOG"; then
    ok "GRAPHICS /PB:STD (loaded with explicit printbox ID, batch continued)"
else
    fail "GRAPHICS /PB:STD (batch hung or crashed)"
fi

if grep -q "GRAPHICS_PRINTBOX_DONE" "$SERIAL_LOG"; then
    ok "GRAPHICS /PRINTBOX:STD (long synonym loaded and batch continued)"
else
    fail "GRAPHICS /PRINTBOX:STD (batch hung or crashed)"
fi

echo ""
echo "--- MODE COM/LPT tests ---"

if grep -q "MODE_COM_DONE" "$SERIAL_LOG"; then
    ok "MODE COM1: 9600,N,8,1 (batch continued after serial port config)"
else
    fail "MODE COM1: 9600,N,8,1 (batch hung or crashed)"
fi

if grep -qi "COM1.*9600" "$SERIAL_LOG"; then
    ok "MODE COM1: (success output confirms 9600 baud)"
else
    fail "MODE COM1: (expected 'COM1: 9600,...' in output)"
fi

if grep -q "MODE_LPT_DONE" "$SERIAL_LOG"; then
    ok "MODE LPT1: 80,6 (batch continued after printer config)"
else
    fail "MODE LPT1: 80,6 (batch hung or crashed)"
fi

if grep -qi "LPT1.*set for 80\|set for 80" "$SERIAL_LOG"; then
    ok "MODE LPT1: (success output: 'set for 80')"
else
    fail "MODE LPT1: (expected 'LPT1: set for 80' in output)"
fi

echo ""
echo "--- FIND stdin tests ---"

if sed -n '/---FIND-STDIN---/,/---DIR-P---/p' "$SERIAL_LOG" | grep -qi "Hello World"; then
    ok "FIND from stdin (ECHO | FIND matched 'Hello World')"
else
    fail "FIND from stdin (expected 'Hello World' in FIND output)"
fi

echo ""
echo "--- DIR /P tests ---"

if grep -q "DIR_P_DONE" "$SERIAL_LOG"; then
    ok "DIR /P (paginated listing completed, batch continued)"
else
    fail "DIR /P (batch hung — pagination pause may not have been dismissed)"
fi

if sed -n '/---DIR-P---/,/DIR_P_DONE/p' "$SERIAL_LOG" | grep -qi "COMMAND.*COM\|Directory of"; then
    ok "DIR /P (directory listing contains files)"
else
    fail "DIR /P (expected file listing in DIR /P output)"
fi

echo ""
echo "--- MODE LPT1:=COM1: redirect tests ---"

if grep -q "MODE_REDIRECT_DONE" "$SERIAL_LOG"; then
    ok "MODE LPT1:=COM1: (batch continued after redirect)"
else
    fail "MODE LPT1:=COM1: (batch hung or crashed)"
fi

if grep -qi "rerouted to COM1\|LPT1.*rerouted" "$SERIAL_LOG"; then
    ok "MODE LPT1:=COM1: (output: 'LPT1: rerouted to COM1:')"
else
    fail "MODE LPT1:=COM1: (expected 'rerouted to COM1' in output)"
fi

echo ""
echo "--- COMMAND /? tests ---"

if grep -qi "Starts a new instance" "$SERIAL_LOG"; then
    ok "COMMAND /? (help text: 'Starts a new instance' printed)"
else
    fail "COMMAND /? (expected 'Starts a new instance' in help output)"
fi

if grep -q "COMMAND_HELP_DONE" "$SERIAL_LOG"; then
    ok "COMMAND /? (batch continued — no crash in /? code path)"
else
    fail "COMMAND /? (batch hung or crashed — possible regression of 58a0bb4)"
fi

echo ""
echo "--- SORT / TREE deployed behavior tests ---"

sort_section=$(sed -n '/---SORT-FILE---/,/SORT_FILE_DONE/p' "$SERIAL_LOG")
apple_line=$(printf '%s\n' "$sort_section" | grep -nix $'apple\r' | cut -d: -f1 || true)
banana_line=$(printf '%s\n' "$sort_section" | grep -nix $'banana\r' | cut -d: -f1 || true)
cherry_line=$(printf '%s\n' "$sort_section" | grep -nix $'cherry\r' | cut -d: -f1 || true)
if [[ -n "$apple_line" && -n "$banana_line" && -n "$cherry_line" ]] \
    && (( apple_line < banana_line && banana_line < cherry_line )); then
    ok "SORT ordered redirected input as apple, banana, cherry"
else
    fail "SORT did not produce the expected ascending records"
fi

if sed -n '/---TREE-FILES---/,/TREE_FILES_DONE/p' "$SERIAL_LOG" \
    | grep -qi 'LEAF.TXT'; then
    ok "TREE /F /A traversed the fixture and listed its leaf file"
else
    fail "TREE /F /A did not expose the fixture hierarchy"
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
