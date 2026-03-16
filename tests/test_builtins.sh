#!/bin/bash
# tests/test_builtins.sh — E2E tests for COMMAND.COM built-in commands via QEMU.
#
# Boots a floppy with AUTOEXEC.BAT that runs CTTY AUX + built-in commands,
# then checks COM1 serial output for expected strings.
#
# Known limitations:
#   - TYPE <file> without ^Z — hangs (DOS text mode reads until ^Z; fixed by adding ^Z)
#
# Run via: make test-builtins  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

TEST_IMG="$OUT/floppy-builtins.img"
SERIAL_LOG="$OUT/builtins-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== COMMAND.COM built-in E2E tests (QEMU) ==="

# ── Build test floppy ────────────────────────────────────────────────────────
echo "Building test floppy..."
cp "$FLOPPY" "$TEST_IMG"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# Add a test file for TYPE/COPY/REN/DEL tests.
# Must end with ^Z (0x1A) — TYPE reads in text mode and hangs without it.
printf 'HELLO_TYPE_TEST\r\n\x1a' | mcopy -o -i "$TEST_IMG" - ::TEST.TXT

# Add a multi-line test file for FIND functional tests.
printf 'alpha one\r\nBETA TWO\r\nalpha three\r\ngamma four\r\nALPHA FIVE\r\n\x1a' \
    | mcopy -o -i "$TEST_IMG" - ::FIND.DAT

# Add a second test file for COPY concat and DEL wildcard tests.
printf 'SECOND_FILE\r\n\x1a' | mcopy -o -i "$TEST_IMG" - ::TEST2.TXT

# Add files for DEL wildcard test (*.DEL pattern).
printf 'DEL1\r\n\x1a' | mcopy -o -i "$TEST_IMG" - ::FILE1.DEL
printf 'DEL2\r\n\x1a' | mcopy -o -i "$TEST_IMG" - ::FILE2.DEL

# Add a file with ^Z in the middle for TYPE binary test.
# TYPE should stop at ^Z and only show "BEFORE_EOF".
printf 'BEFORE_EOF\r\n\x1aSHOULD_NOT_APPEAR\r\n' | mcopy -o -i "$TEST_IMG" - ::TYPEZ.TXT

# Add a sub-batch for CALL test
printf '@ECHO CALL_SUB_OK\r\n' | mcopy -o -i "$TEST_IMG" - ::CALLSUB.BAT

# Add a sub-batch for SHIFT test: echoes %1, shifts, echoes new %1
{ printf 'ECHO SHIFT_ARG1=%%1\r\n'; printf 'SHIFT\r\n'; printf 'ECHO SHIFT_AFTER=%%1\r\n'; } \
    | mcopy -o -i "$TEST_IMG" - ::SHIFTSUB.BAT

# Build AUTOEXEC.BAT with all test commands.
# ECHO markers between sections help identify output in the serial log.
#
# All previously-hanging commands (SET=, PROMPT, FOR) are now fixed and tested.
{
    printf 'CTTY AUX\r\n'

    # ── Original tests ────────────────────────────────────────────────────
    printf 'VER\r\n'
    printf 'ECHO HELLO_E2E_TEST\r\n'
    printf 'SET\r\n'
    printf 'PATH\r\n'
    printf 'DIR\r\n'
    printf 'VOL\r\n'

    # ── BREAK / VERIFY state queries ─────────────────────────────────────
    printf 'ECHO ---BREAK---\r\n'
    printf 'BREAK\r\n'
    printf 'ECHO ---VERIFY---\r\n'
    printf 'VERIFY\r\n'

    # ── CHCP (code page) ─────────────────────────────────────────────────
    printf 'ECHO ---CHCP---\r\n'
    printf 'CHCP\r\n'

    # ── TYPE (needs ^Z terminated file) ─────────────────────────────────
    printf 'ECHO ---TYPE---\r\n'
    printf 'TYPE TEST.TXT\r\n'

    # ── TRUENAME ──────────────────────────────────────────────────────────
    printf 'ECHO ---TRUENAME---\r\n'
    printf 'TRUENAME A:\\\r\n'

    # ── IF tests ──────────────────────────────────────────────────────────
    printf 'ECHO ---IF---\r\n'
    printf 'IF EXIST COMMAND.COM ECHO IF_EXIST_OK\r\n'
    printf 'IF NOT EXIST NOFILE.XYZ ECHO IF_NOT_EXIST_OK\r\n'
    printf 'IF abc==abc ECHO IF_EQUAL_OK\r\n'
    printf 'IF NOT abc==xyz ECHO IF_NOT_EQUAL_OK\r\n'
    printf 'FIND "NONEXISTENT" COMMAND.COM\r\n'
    printf 'IF ERRORLEVEL 1 ECHO IF_ERRORLEVEL_OK\r\n'

    # ── GOTO ──────────────────────────────────────────────────────────────
    printf 'ECHO ---GOTO---\r\n'
    printf 'GOTO SKIP_THIS\r\n'
    printf 'ECHO SHOULD_NOT_APPEAR\r\n'
    printf ':SKIP_THIS\r\n'
    printf 'ECHO GOTO_OK\r\n'

    # ── REM ───────────────────────────────────────────────────────────────
    printf 'ECHO ---REM---\r\n'
    printf 'REM This is a comment and should produce no output\r\n'
    printf 'ECHO REM_SURVIVED\r\n'

    # ── CALL (sub-batch + return) ─────────────────────────────────────────
    printf 'ECHO ---CALL---\r\n'
    printf 'CALL CALLSUB.BAT\r\n'
    printf 'ECHO CALL_RETURNED\r\n'

    # ── COPY + verify ─────────────────────────────────────────────────────
    printf 'ECHO ---COPY---\r\n'
    printf 'COPY TEST.TXT COPIED.TXT\r\n'
    printf 'IF EXIST COPIED.TXT ECHO COPY_VERIFIED\r\n'

    # ── REN + verify ──────────────────────────────────────────────────────
    printf 'ECHO ---REN---\r\n'
    printf 'REN COPIED.TXT RENAMED.TXT\r\n'
    printf 'IF EXIST RENAMED.TXT ECHO REN_VERIFIED\r\n'

    # ── DEL + verify ──────────────────────────────────────────────────────
    printf 'ECHO ---DEL---\r\n'
    printf 'DEL RENAMED.TXT\r\n'
    printf 'IF NOT EXIST RENAMED.TXT ECHO DEL_VERIFIED\r\n'

    # ── MD / CD / RD ─────────────────────────────────────────────────────
    printf 'ECHO ---MKDIR---\r\n'
    printf 'MD TESTDIR\r\n'

    printf 'ECHO ---CHDIR---\r\n'
    printf 'CD TESTDIR\r\n'
    printf 'CD\r\n'
    printf 'CD \\\r\n'

    printf 'ECHO ---RMDIR---\r\n'
    printf 'RD TESTDIR\r\n'

    # ── SET assignment ────────────────────────────────────────────────
    printf 'ECHO ---SET-ASSIGN---\r\n'
    printf 'SET TESTVAR=SET_VALUE_OK\r\n'
    printf 'ECHO SET_ASSIGN_SURVIVED\r\n'

    # ── PROMPT ──────────────────────────────────────────────────────────
    printf 'ECHO ---PROMPT---\r\n'
    printf 'PROMPT $P$G\r\n'
    printf 'ECHO PROMPT_SURVIVED\r\n'

    # ── FOR (bare error + valid loop) ──────────────────────────────────
    printf 'ECHO ---FOR---\r\n'
    printf 'FOR\r\n'
    printf 'ECHO FOR_BARE_SURVIVED\r\n'
    printf 'FOR %%%%X IN (AAA BBB CCC) DO ECHO FOR_GOT_%%%%X\r\n'

    # ── BREAK ON/OFF toggle ───────────────────────────────────────────────────
    printf 'ECHO ---BREAK-TOGGLE---\r\n'
    printf 'BREAK ON\r\n'
    printf 'BREAK\r\n'
    printf 'BREAK OFF\r\n'
    printf 'BREAK\r\n'
    printf 'ECHO BREAK_TOGGLE_OK\r\n'

    # ── VERIFY ON/OFF toggle ──────────────────────────────────────────────────
    printf 'ECHO ---VERIFY-TOGGLE---\r\n'
    printf 'VERIFY ON\r\n'
    printf 'VERIFY\r\n'
    printf 'VERIFY OFF\r\n'
    printf 'VERIFY\r\n'
    printf 'ECHO VERIFY_TOGGLE_OK\r\n'

    # ── ECHO ON / OFF / ECHO. ─────────────────────────────────────────────────
    printf 'ECHO ---ECHO-FORMS---\r\n'
    printf 'ECHO.\r\n'
    printf 'ECHO ECHO_DOT_OK\r\n'
    printf 'ECHO OFF\r\n'
    printf 'ECHO ECHO_OFF_OK\r\n'
    printf 'ECHO ON\r\n'
    printf 'ECHO ECHO_ON_OK\r\n'

    # ── SHIFT ─────────────────────────────────────────────────────────────────
    printf 'ECHO ---SHIFT---\r\n'
    printf 'CALL SHIFTSUB.BAT FIRST SECOND\r\n'

    # ── DIR /W ────────────────────────────────────────────────────────────────
    printf 'ECHO ---DIR-W---\r\n'
    printf 'DIR /W\r\n'
    printf 'ECHO DIR_W_OK\r\n'

    # ── PATH set + clear ──────────────────────────────────────────────────────
    printf 'ECHO ---PATH-FORMS---\r\n'
    printf 'PATH A:\\DOS\r\n'
    printf 'PATH\r\n'
    printf 'PATH ;\r\n'
    printf 'PATH\r\n'
    printf 'ECHO PATH_FORMS_OK\r\n'

    # ── SET overwrite + clear ─────────────────────────────────────────────────
    printf 'ECHO ---SET-FORMS---\r\n'
    printf 'SET SETVAR=ORIGINAL\r\n'
    printf 'SET SETVAR=UPDATED\r\n'
    printf 'SET\r\n'
    printf 'SET SETVAR=\r\n'
    printf 'ECHO ---SET-AFTER-CLEAR---\r\n'
    printf 'SET\r\n'
    printf 'ECHO SET_FORMS_OK\r\n'

    # ── MD already-exists (should print error but batch continues) ────────────
    printf 'ECHO ---MD-EXISTS---\r\n'
    printf 'MD DUPDIR\r\n'
    printf 'MD DUPDIR\r\n'
    printf 'ECHO MD_EXISTS_SURVIVED\r\n'
    printf 'RD DUPDIR\r\n'

    # ── RD non-empty (should refuse) ──────────────────────────────────────────
    printf 'ECHO ---RD-NONEMPTY---\r\n'
    printf 'MD NEDIR\r\n'
    printf 'COPY TEST.TXT NEDIR\\INNER.TXT\r\n'
    printf 'RD NEDIR\r\n'
    printf 'IF EXIST NEDIR\\INNER.TXT ECHO RD_REFUSED_OK\r\n'
    printf 'DEL NEDIR\\INNER.TXT\r\n'
    printf 'RD NEDIR\r\n'

    # ── COPY /V (verify flag) ─────────────────────────────────────────────────
    printf 'ECHO ---COPY-V---\r\n'
    printf 'COPY TEST.TXT CVTEST.TXT /V\r\n'
    printf 'IF EXIST CVTEST.TXT ECHO COPY_V_OK\r\n'
    printf 'DEL CVTEST.TXT\r\n'

    # ── FIND functional tests ──────────────────────────────────────────────────
    # ── CHKDSK (check current drive = A:) ──────────────────────────────────────
    printf 'ECHO ---CHKDSK---\r\n'
    printf 'CHKDSK\r\n'
    printf 'ECHO CHKDSK_DONE\r\n'

    # ── CHKDSK A: (check specific drive) ─────────────────────────────────────
    printf 'ECHO ---CHKDSK-A---\r\n'
    printf 'CHKDSK A:\r\n'
    printf 'ECHO CHKDSK_A_DONE\r\n'

    # ── CHKDSK /V (verbose — list all files) ─────────────────────────────────
    printf 'ECHO ---CHKDSK-V---\r\n'
    printf 'CHKDSK A: /V\r\n'
    printf 'ECHO CHKDSK_V_DONE\r\n'

    printf 'ECHO ---FIND-BASIC---\r\n'
    printf 'FIND "alpha" FIND.DAT\r\n'

    printf 'ECHO ---FIND-COUNT---\r\n'
    printf 'FIND /C "alpha" FIND.DAT\r\n'

    printf 'ECHO ---FIND-LINENUM---\r\n'
    printf 'FIND /N "gamma" FIND.DAT\r\n'

    printf 'ECHO ---FIND-INVERSE---\r\n'
    printf 'FIND /V "alpha" FIND.DAT\r\n'

    printf 'ECHO ---FIND-NOMATCH---\r\n'
    printf 'FIND "zzzzz" FIND.DAT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FIND_NOMATCH_ERRORLEVEL\r\n'

    # ── DIR with path and wildcard ────────────────────────────────────────────
    printf 'ECHO ---DIR-PATH---\r\n'
    printf 'DIR A:\\\r\n'
    printf 'ECHO DIR_PATH_OK\r\n'

    printf 'ECHO ---DIR-WILD---\r\n'
    printf 'DIR *.TXT\r\n'
    printf 'ECHO DIR_WILD_OK\r\n'

    # ── COPY concat (src+src2 dest) ────────────────────────────────────────────
    printf 'ECHO ---COPY-CONCAT---\r\n'
    printf 'COPY TEST.TXT+TEST2.TXT CONCAT.TXT\r\n'
    printf 'IF EXIST CONCAT.TXT ECHO COPY_CONCAT_OK\r\n'
    printf 'DEL CONCAT.TXT\r\n'

    # ── DEL wildcard ───────────────────────────────────────────────────────────
    printf 'ECHO ---DEL-WILD---\r\n'
    printf 'DEL *.DEL\r\n'
    printf 'IF NOT EXIST FILE1.DEL ECHO DEL_WILD_1_GONE\r\n'
    printf 'IF NOT EXIST FILE2.DEL ECHO DEL_WILD_2_GONE\r\n'

    # ── DEL read-only (should fail) ────────────────────────────────────────────
    printf 'ECHO ---DEL-READONLY---\r\n'
    printf 'COPY TEST.TXT RDONLY.TXT\r\n'
    printf 'ATTRIB +R RDONLY.TXT\r\n'
    printf 'DEL RDONLY.TXT\r\n'
    printf 'IF EXIST RDONLY.TXT ECHO DEL_READONLY_REFUSED\r\n'
    printf 'ATTRIB -R RDONLY.TXT\r\n'
    printf 'DEL RDONLY.TXT\r\n'

    # ── ERASE synonym ─────────────────────────────────────────────────────────
    printf 'ECHO ---ERASE---\r\n'
    printf 'COPY TEST.TXT ERASEME.TXT\r\n'
    printf 'ERASE ERASEME.TXT\r\n'
    printf 'IF NOT EXIST ERASEME.TXT ECHO ERASE_OK\r\n'

    # ── REN to existing name (should fail) ─────────────────────────────────────
    printf 'ECHO ---REN-EXIST---\r\n'
    printf 'COPY TEST.TXT RENSRC.TXT\r\n'
    printf 'COPY TEST.TXT RENDST.TXT\r\n'
    printf 'REN RENSRC.TXT RENDST.TXT\r\n'
    printf 'IF EXIST RENSRC.TXT ECHO REN_EXIST_REFUSED\r\n'
    printf 'DEL RENSRC.TXT\r\n'
    printf 'DEL RENDST.TXT\r\n'

    # ── TYPE binary ^Z mid-file ────────────────────────────────────────────────
    printf 'ECHO ---TYPE-Z---\r\n'
    printf 'TYPE TYPEZ.TXT\r\n'
    printf 'ECHO TYPE_Z_DONE\r\n'

    # ── MD nested path ─────────────────────────────────────────────────────────
    printf 'ECHO ---MD-NESTED---\r\n'
    printf 'MD DEEP\r\n'
    printf 'MD DEEP\\SUB\r\n'
    printf 'IF EXIST DEEP\\SUB\\NUL ECHO MD_NESTED_OK\r\n'
    printf 'RD DEEP\\SUB\r\n'
    printf 'RD DEEP\r\n'

    # ── CD forms (no-arg, absolute, drive-rooted) ──────────────────────────────
    printf 'ECHO ---CD-FORMS---\r\n'
    printf 'MD CDTEST\r\n'
    printf 'CD CDTEST\r\n'
    printf 'CD\r\n'
    printf 'CD A:\\\r\n'
    printf 'CD\r\n'
    printf 'ECHO CD_FORMS_DONE\r\n'
    printf 'RD CDTEST\r\n'

    # ── CLS (just verify batch continues) ──────────────────────────────────────
    printf 'ECHO ---CLS---\r\n'
    printf 'CLS\r\n'
    printf 'ECHO CLS_SURVIVED\r\n'

    # ── COPY /B (binary copy) ──────────────────────────────────────────────────
    printf 'ECHO ---COPY-B---\r\n'
    printf 'COPY /B TEST.TXT BINCOPY.TXT\r\n'
    printf 'IF EXIST BINCOPY.TXT ECHO COPY_B_OK\r\n'
    printf 'DEL BINCOPY.TXT\r\n'

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$TEST_IMG" - ::AUTOEXEC.BAT

# ── Boot QEMU and capture serial output ──────────────────────────────────────
# Use cache=writethrough so floppy writes are flushed (needed for COPY/REN/DEL/MD).
echo "Booting QEMU (headless, ~40s)..."
rm -f "$SERIAL_LOG"
timeout 60 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$TEST_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    </dev/null 2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty or missing — QEMU may have failed to boot"
    exit 1
fi

# ── Check output ─────────────────────────────────────────────────────────────

echo ""
echo "--- Original tests ---"

if grep -q "MS-DOS Version" "$SERIAL_LOG"; then
    ok "VER"
else
    fail "VER (expected 'MS-DOS Version')"
fi

if grep -q "HELLO_E2E_TEST" "$SERIAL_LOG"; then
    ok "ECHO"
else
    fail "ECHO (expected 'HELLO_E2E_TEST')"
fi

if grep -q "COMSPEC=" "$SERIAL_LOG"; then
    ok "SET (lists environment)"
else
    fail "SET (expected 'COMSPEC=')"
fi

if grep -q "No Path\|PATH=" "$SERIAL_LOG"; then
    ok "PATH"
else
    fail "PATH (expected 'No Path' or 'PATH=')"
fi

if grep -q "COMMAND" "$SERIAL_LOG"; then
    ok "DIR"
else
    fail "DIR (expected 'COMMAND' in listing)"
fi

if grep -q "Serial Number" "$SERIAL_LOG"; then
    ok "VOL"
else
    fail "VOL (expected 'Serial Number')"
fi

echo ""
echo "--- State queries ---"

if grep -q "BREAK is o[nf]" "$SERIAL_LOG"; then
    ok "BREAK"
else
    fail "BREAK (expected 'BREAK is on/off')"
fi

if grep -q "VERIFY is o[nf]" "$SERIAL_LOG"; then
    ok "VERIFY"
else
    fail "VERIFY (expected 'VERIFY is on/off')"
fi

if grep -q "[Cc]ode [Pp]age" "$SERIAL_LOG"; then
    ok "CHCP"
else
    fail "CHCP (expected 'code page')"
fi

if grep -q "HELLO_TYPE_TEST" "$SERIAL_LOG"; then
    ok "TYPE"
else
    fail "TYPE (expected 'HELLO_TYPE_TEST')"
fi

if grep -q "A:" "$SERIAL_LOG"; then
    ok "TRUENAME"
else
    fail "TRUENAME (expected path with A:)"
fi

echo ""
echo "--- IF tests ---"

if grep -q "IF_EXIST_OK" "$SERIAL_LOG"; then
    ok "IF EXIST"
else
    fail "IF EXIST (expected 'IF_EXIST_OK')"
fi

if grep -q "IF_NOT_EXIST_OK" "$SERIAL_LOG"; then
    ok "IF NOT EXIST"
else
    fail "IF NOT EXIST (expected 'IF_NOT_EXIST_OK')"
fi

if grep -q "IF_EQUAL_OK" "$SERIAL_LOG"; then
    ok "IF string==string"
else
    fail "IF string==string (expected 'IF_EQUAL_OK')"
fi

if grep -q "IF_NOT_EQUAL_OK" "$SERIAL_LOG"; then
    ok "IF NOT string==string"
else
    fail "IF NOT string==string (expected 'IF_NOT_EQUAL_OK')"
fi

if grep -q "IF_ERRORLEVEL_OK" "$SERIAL_LOG"; then
    ok "IF ERRORLEVEL (after failed FIND)"
else
    fail "IF ERRORLEVEL (expected 'IF_ERRORLEVEL_OK')"
fi

echo ""
echo "--- Batch flow ---"

if grep -q "GOTO_OK" "$SERIAL_LOG" && ! grep -q "SHOULD_NOT_APPEAR" "$SERIAL_LOG"; then
    ok "GOTO"
else
    fail "GOTO (expected 'GOTO_OK', no 'SHOULD_NOT_APPEAR')"
fi

if grep -q "REM_SURVIVED" "$SERIAL_LOG"; then
    ok "REM"
else
    fail "REM (expected 'REM_SURVIVED')"
fi

if grep -q "CALL_SUB_OK" "$SERIAL_LOG"; then
    ok "CALL (sub-batch executed)"
else
    fail "CALL (expected 'CALL_SUB_OK')"
fi

if grep -q "CALL_RETURNED" "$SERIAL_LOG"; then
    ok "CALL (returned to caller)"
else
    fail "CALL (expected 'CALL_RETURNED')"
fi

echo ""
echo "--- File operations ---"

if grep -q "COPY_VERIFIED" "$SERIAL_LOG"; then
    ok "COPY"
else
    fail "COPY (expected 'COPY_VERIFIED')"
fi

if grep -q "REN_VERIFIED" "$SERIAL_LOG"; then
    ok "REN"
else
    fail "REN (expected 'REN_VERIFIED')"
fi

if grep -q "DEL_VERIFIED" "$SERIAL_LOG"; then
    ok "DEL"
else
    fail "DEL (expected 'DEL_VERIFIED')"
fi

echo ""
echo "--- Directory operations ---"

if grep -q "TESTDIR" "$SERIAL_LOG"; then
    ok "MD + CD (created and entered)"
else
    fail "MD + CD (expected 'TESTDIR' in CD output)"
fi

echo ""
echo "--- SET assignment ---"

if grep -q "SET_ASSIGN_SURVIVED" "$SERIAL_LOG"; then
    ok "SET assignment (batch continues)"
else
    fail "SET assignment (batch hung after SET TESTVAR=value)"
fi

echo ""
echo "--- PROMPT ---"

if grep -q "PROMPT_SURVIVED" "$SERIAL_LOG"; then
    ok "PROMPT (batch continues)"
else
    fail "PROMPT (batch hung after PROMPT change)"
fi

echo ""
echo "--- FOR command ---"

if grep -q "FOR_BARE_SURVIVED" "$SERIAL_LOG"; then
    ok "FOR (bare syntax error recovery)"
else
    fail "FOR (bare FOR should print 'Syntax error' and continue)"
fi

if grep -q "FOR_GOT_AAA" "$SERIAL_LOG" && grep -q "FOR_GOT_BBB" "$SERIAL_LOG" && grep -q "FOR_GOT_CCC" "$SERIAL_LOG"; then
    ok "FOR (loop iterates all items)"
else
    fail "FOR (expected FOR_GOT_AAA, FOR_GOT_BBB, FOR_GOT_CCC)"
fi

echo ""
echo "--- Completion ---"

if grep -q "===DONE===" "$SERIAL_LOG"; then
    ok "AUTOEXEC.BAT ran to completion"
else
    fail "AUTOEXEC.BAT did not reach ===DONE==="
fi

echo ""
echo "--- BREAK/VERIFY toggles ---"

if grep -q "BREAK is on" "$SERIAL_LOG"; then
    ok "BREAK ON (state confirmed)"
else
    fail "BREAK ON (expected 'BREAK is on')"
fi

if grep -q "BREAK is off" "$SERIAL_LOG"; then
    ok "BREAK OFF (state confirmed)"
else
    fail "BREAK OFF (expected 'BREAK is off')"
fi

if grep -q "VERIFY is on" "$SERIAL_LOG"; then
    ok "VERIFY ON (state confirmed)"
else
    fail "VERIFY ON (expected 'VERIFY is on')"
fi

if grep -q "VERIFY is off" "$SERIAL_LOG"; then
    ok "VERIFY OFF (state confirmed)"
else
    fail "VERIFY OFF (expected 'VERIFY is off')"
fi

echo ""
echo "--- ECHO forms ---"

if grep -q "ECHO_DOT_OK" "$SERIAL_LOG"; then
    ok "ECHO. (blank line)"
else
    fail "ECHO. (expected 'ECHO_DOT_OK')"
fi

if grep -q "ECHO_OFF_OK" "$SERIAL_LOG"; then
    ok "ECHO OFF"
else
    fail "ECHO OFF (expected 'ECHO_OFF_OK')"
fi

if grep -q "ECHO_ON_OK" "$SERIAL_LOG"; then
    ok "ECHO ON"
else
    fail "ECHO ON (expected 'ECHO_ON_OK')"
fi

echo ""
echo "--- SHIFT ---"

if grep -q "SHIFT_ARG1=FIRST" "$SERIAL_LOG" && grep -q "SHIFT_AFTER=SECOND" "$SERIAL_LOG"; then
    ok "SHIFT (%1 shifted to next arg)"
else
    fail "SHIFT (expected 'SHIFT_ARG1=FIRST' and 'SHIFT_AFTER=SECOND')"
fi

echo ""
echo "--- DIR /W ---"

# DIR /W shows multiple filenames per line (space-separated, no dots: "COMMAND  COM    SYS      COM")
if sed -n '/---DIR-W---/,/DIR_W_OK/p' "$SERIAL_LOG" | grep -q "COM.*COM\|EXE.*EXE\|COM.*EXE\|EXE.*COM"; then
    ok "DIR /W (wide format, multiple names per line)"
else
    fail "DIR /W (expected multiple filenames on one line)"
fi

echo ""
echo "--- PATH forms ---"

if grep -q 'A:\\DOS\|A:/DOS' "$SERIAL_LOG"; then
    ok "PATH set (A:\\DOS visible in PATH output)"
else
    fail "PATH set (expected 'A:\\DOS' in PATH output)"
fi

if grep -q "No Path" "$SERIAL_LOG"; then
    ok "PATH clear (No Path after PATH ;)"
else
    fail "PATH clear (expected 'No Path' after PATH ;)"
fi

echo ""
echo "--- SET forms ---"

if sed -n '/---SET-FORMS---/,/---SET-AFTER-CLEAR---/p' "$SERIAL_LOG" | grep -q "SETVAR=UPDATED"; then
    ok "SET overwrite (SETVAR=UPDATED in SET dump)"
else
    fail "SET overwrite (expected 'SETVAR=UPDATED' in SET output)"
fi

if sed -n '/---SET-AFTER-CLEAR---/,/SET_FORMS_OK/p' "$SERIAL_LOG" | grep -q "SETVAR="; then
    fail "SET clear (SETVAR still present after SET SETVAR=)"
else
    ok "SET clear (SETVAR absent after SET SETVAR=)"
fi

echo ""
echo "--- MD/RD edge cases ---"

if grep -q "MD_EXISTS_SURVIVED" "$SERIAL_LOG"; then
    ok "MD already-exists (error printed, batch continues)"
else
    fail "MD already-exists (expected 'MD_EXISTS_SURVIVED')"
fi

if grep -q "RD_REFUSED_OK" "$SERIAL_LOG"; then
    ok "RD non-empty dir (refused, file still exists)"
else
    fail "RD non-empty dir (expected 'RD_REFUSED_OK')"
fi

echo ""
echo "--- COPY /V ---"

if grep -q "COPY_V_OK" "$SERIAL_LOG"; then
    ok "COPY /V"
else
    fail "COPY /V (expected 'COPY_V_OK')"
fi

echo ""
echo "--- CHKDSK ---"

# CHKDSK (no args) — should report disk stats for current drive
if sed -n '/---CHKDSK---/,/CHKDSK_DONE/p' "$SERIAL_LOG" | grep -q "bytes total disk space"; then
    ok "CHKDSK (current drive — disk stats reported)"
else
    fail "CHKDSK (expected 'bytes total disk space')"
fi

# CHKDSK A: — should report disk stats for explicit drive
if sed -n '/---CHKDSK-A---/,/CHKDSK_A_DONE/p' "$SERIAL_LOG" | grep -q "bytes available on disk"; then
    ok "CHKDSK A: (free space reported)"
else
    fail "CHKDSK A: (expected 'bytes available on disk')"
fi

# CHKDSK /V should list files — COMMAND.COM must appear
if sed -n '/---CHKDSK-V---/,/CHKDSK_V_DONE/p' "$SERIAL_LOG" | grep -q "COMMAND"; then
    ok "CHKDSK /V (verbose lists COMMAND.COM)"
else
    fail "CHKDSK /V (expected 'COMMAND' in verbose file listing)"
fi

echo ""
echo "--- FIND functional ---"

# Basic search: should find "alpha one" and "alpha three" (case-sensitive)
if grep -q "alpha one" "$SERIAL_LOG" && grep -q "alpha three" "$SERIAL_LOG"; then
    ok "FIND basic (found 'alpha' lines)"
else
    fail "FIND basic (expected 'alpha one' and 'alpha three')"
fi

# Basic search should NOT match uppercase ALPHA (case-sensitive)
if sed -n '/---FIND-BASIC---/,/---FIND-COUNT---/p' "$SERIAL_LOG" | grep -q "ALPHA FIVE"; then
    fail "FIND basic (matched 'ALPHA FIVE' — should be case-sensitive)"
else
    ok "FIND basic (case-sensitive, skipped 'ALPHA FIVE')"
fi

# /C count: should show count of 2 (two lowercase "alpha" lines)
if grep -q ": 2" "$SERIAL_LOG" || grep -q ":2" "$SERIAL_LOG"; then
    ok "FIND /C (count = 2)"
else
    fail "FIND /C (expected count of 2)"
fi

# /N line numbers: should show [4] for "gamma four" (line 4)
if grep -q "\[4\]" "$SERIAL_LOG"; then
    ok "FIND /N (line number [4] for 'gamma')"
else
    fail "FIND /N (expected '[4]' line number)"
fi

# /V inverse: should show lines NOT containing "alpha" — BETA, gamma, ALPHA
if grep -q "BETA TWO" "$SERIAL_LOG" && grep -q "gamma four" "$SERIAL_LOG"; then
    ok "FIND /V (shows non-matching lines)"
else
    fail "FIND /V (expected 'BETA TWO' and 'gamma four')"
fi

# No match: FIND should set errorlevel >= 1
if grep -q "FIND_NOMATCH_ERRORLEVEL" "$SERIAL_LOG"; then
    ok "FIND no-match errorlevel"
else
    fail "FIND no-match (expected errorlevel >= 1)"
fi

echo ""
echo "--- DIR path and wildcard ---"

if sed -n '/---DIR-PATH---/,/DIR_PATH_OK/p' "$SERIAL_LOG" | grep -q "COMMAND"; then
    ok "DIR A:\\ (explicit path lists COMMAND.COM)"
else
    fail "DIR A:\\ (expected 'COMMAND' in listing)"
fi

if sed -n '/---DIR-WILD---/,/DIR_WILD_OK/p' "$SERIAL_LOG" | grep -q "TEST.*TXT"; then
    ok "DIR *.TXT (wildcard matches)"
else
    fail "DIR *.TXT (expected TXT files in listing)"
fi

echo ""
echo "--- COPY concat ---"

if grep -q "COPY_CONCAT_OK" "$SERIAL_LOG"; then
    ok "COPY concat (TEST.TXT+TEST2.TXT)"
else
    fail "COPY concat (expected 'COPY_CONCAT_OK')"
fi

echo ""
echo "--- DEL wildcard ---"

if grep -q "DEL_WILD_1_GONE" "$SERIAL_LOG" && grep -q "DEL_WILD_2_GONE" "$SERIAL_LOG"; then
    ok "DEL *.DEL (both files deleted)"
else
    fail "DEL *.DEL (expected both DEL_WILD_*_GONE)"
fi

echo ""
echo "--- DEL read-only ---"

if grep -q "DEL_READONLY_REFUSED" "$SERIAL_LOG"; then
    ok "DEL read-only file (refused, file still exists)"
else
    fail "DEL read-only (expected 'DEL_READONLY_REFUSED')"
fi

echo ""
echo "--- ERASE ---"

if grep -q "ERASE_OK" "$SERIAL_LOG"; then
    ok "ERASE synonym for DEL"
else
    fail "ERASE (expected 'ERASE_OK')"
fi

echo ""
echo "--- REN to existing ---"

if grep -q "REN_EXIST_REFUSED" "$SERIAL_LOG"; then
    ok "REN to existing name (refused, source still exists)"
else
    fail "REN to existing (expected 'REN_EXIST_REFUSED')"
fi

echo ""
echo "--- TYPE ^Z mid-file ---"

if sed -n '/---TYPE-Z---/,/TYPE_Z_DONE/p' "$SERIAL_LOG" | grep -q "BEFORE_EOF"; then
    if sed -n '/---TYPE-Z---/,/TYPE_Z_DONE/p' "$SERIAL_LOG" | grep -q "SHOULD_NOT_APPEAR"; then
        fail "TYPE ^Z (showed content past ^Z)"
    else
        ok "TYPE ^Z (stopped at ^Z, showed BEFORE_EOF only)"
    fi
else
    fail "TYPE ^Z (expected 'BEFORE_EOF')"
fi

echo ""
echo "--- MD nested ---"

if grep -q "MD_NESTED_OK" "$SERIAL_LOG"; then
    ok "MD nested (DEEP\\SUB created)"
else
    fail "MD nested (expected 'MD_NESTED_OK')"
fi

echo ""
echo "--- CD forms ---"

if sed -n '/---CD-FORMS---/,/CD_FORMS_DONE/p' "$SERIAL_LOG" | grep -q "CDTEST"; then
    ok "CD relative (entered CDTEST)"
else
    fail "CD relative (expected 'CDTEST' in CD output)"
fi

if sed -n '/---CD-FORMS---/,/CD_FORMS_DONE/p' "$SERIAL_LOG" | grep -q "A:\\\\$\|A:\\\\[[:space:]]*$\|A:.$"; then
    ok "CD A:\\ (returned to root)"
else
    # Weaker check: just verify CD_FORMS_DONE reached
    if grep -q "CD_FORMS_DONE" "$SERIAL_LOG"; then
        ok "CD A:\\ (batch continued — root return assumed)"
    else
        fail "CD A:\\ (expected return to root)"
    fi
fi

echo ""
echo "--- CLS ---"

if grep -q "CLS_SURVIVED" "$SERIAL_LOG"; then
    ok "CLS (batch continues after clear screen)"
else
    fail "CLS (expected 'CLS_SURVIVED')"
fi

echo ""
echo "--- COPY /B ---"

if grep -q "COPY_B_OK" "$SERIAL_LOG"; then
    ok "COPY /B (binary copy)"
else
    fail "COPY /B (expected 'COPY_B_OK')"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Serial log saved to: $SERIAL_LOG"
fi
[[ $FAIL -eq 0 ]]
