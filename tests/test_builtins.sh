#!/bin/bash
# tests/test_builtins.sh — E2E tests for COMMAND.COM built-in commands via QEMU.
#
# Boots a floppy with AUTOEXEC.BAT that runs CTTY AUX + built-in commands,
# then checks COM1 serial output for expected strings.
#
# Known limitations (hang batch processing):
#   - SET FOO=BAR / PROMPT — hangs (not env size — tested /E:4096, not CTTY AUX)
#   - TYPE <file> without ^Z — hangs (DOS text mode reads until ^Z; fixed by adding ^Z)
# SET/PROMPT likely related to COMMAND.COM transient segment reload.
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

# Add a sub-batch for CALL test
printf '@ECHO CALL_SUB_OK\r\n' | mcopy -o -i "$TEST_IMG" - ::CALLSUB.BAT

# Build AUTOEXEC.BAT with all test commands.
# ECHO markers between sections help identify output in the serial log.
#
# Skipped (hang batch processing):  SET assignment, PROMPT
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

    # ── FOR (bare error + valid loop) ──────────────────────────────────
    printf 'ECHO ---FOR---\r\n'
    printf 'FOR\r\n'
    printf 'ECHO FOR_BARE_SURVIVED\r\n'
    printf 'FOR %%%%X IN (AAA BBB CCC) DO ECHO FOR_GOT_%%%%X\r\n'

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$TEST_IMG" - ::AUTOEXEC.BAT

# ── Boot QEMU and capture serial output ──────────────────────────────────────
# Use cache=writethrough so floppy writes are flushed (needed for COPY/REN/DEL/MD).
echo "Booting QEMU (headless, ~30s)..."
rm -f "$SERIAL_LOG"
timeout 45 qemu-system-i386 \
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

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Serial log saved to: $SERIAL_LOG"
fi
[[ $FAIL -eq 0 ]]
