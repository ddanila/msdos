#!/bin/bash
# tests/test_share_nlsfunc_exe2bin.sh — E2E tests for SHARE, NLSFUNC, EXE2BIN via QEMU.
#
# All three tools in one QEMU boot; no interactive prompts needed.
#
# SHARE (GSHARE2.ASM):
#   - First call: installs as TSR (INT 2Fh hook + INT 21h/31h Keep_Process). No output.
#   - Second call: INT 2Fh check returns AL=0FFh (already loaded) → ShDispMsg prints
#     "SHARE already installed" (COMMON2: "%1 already installed") → exits with AL=0FFh
#     (errorlevel 255) via ShDispMsg's INT 21h/AH=4Ch.
#
# NLSFUNC (NLSFUNC.ASM):
#   - First call (no args): NO_PARMS=1 → installs via INT 2Fh hook + INT 21h/31h. No output.
#   - Second call: INT 2Fh/AH=MULT_NLSFUNC check returns AL≠0 (already installed) →
#     prints "NLSFUNC already installed" (COMMON2) + ERROR_CODE=80h → exits AL=0x80
#     (errorlevel 128) via INT 21h/AH=4Ch.
#   - COUNTRY.SYS path is stored for later TSR use; file need not exist at install time.
#
# EXE2BIN (E2BINIT.ASM):
#   - Converts EXE to binary. Always exits errorlevel 0 (xor al,al before Dos_call Exit).
#   - Success: no output; verifiable via IF EXIST on the output file.
#   - IP=0 in EXE header → BINFIX path → binary conversion (no "Fix-ups" prompt).
#   - IP=0x100 → COM conversion. IP≠0 + fixups → prompts interactively (not tested here).
#   - File not found: DosError → INT 21h/AH=59h → extend_message → "File not found".
#
# Run via: make test-share-nlsfunc-exe2bin  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/floppy-share-nlsfunc-boot.img"
SERIAL_LOG="$OUT/share-nlsfunc-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== SHARE / NLSFUNC / EXE2BIN E2E tests (QEMU) ==="

# ── Step 1: build boot floppy ────────────────────────────────────────────────
echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# Minimal valid EXE for EXE2BIN conversion test.
# MZ header (28 bytes) + 4 bytes padding = 32-byte header (e_cparhdr=2 paragraphs).
# e_ip=0 → BINFIX path in EXE2BIN (binary conversion, no "Fix-ups needed" prompt).
# e_crlc=0 → no relocations → no segment prompt.
# e_cp=1, e_cblp=33 → total file = 33 bytes (32 header + 1 byte code).
# Code = 0xC3 (RET) — any single byte works; EXE2BIN just copies it verbatim.
#
# Offsets: MZ(0) cblp(2) cp(4) crlc(6) cparhdr(8) minalloc(10) maxalloc(12)
#          ss(14) sp(16) csum(18) ip(20) cs(22) lfarlc(24) ovno(26) pad(28) code(32)
printf '\115\132\041\000\001\000\000\000\002\000\000\000\377\377\000\000\000\000\000\000\000\000\000\000\034\000\000\000\000\000\000\000\303' \
    | mcopy -o -i "$BOOT_IMG" - ::TEST.EXE

{
    printf 'CTTY AUX\r\n'

    # ── SHARE (first call) — load file-sharing TSR ────────────────────────────
    # No output on success. Hooks INT 2Fh, calls INT 21h/31h (Keep_Process).
    printf 'ECHO ---SHARE---\r\n'
    printf 'SHARE\r\n'
    printf 'ECHO SHARE_DONE\r\n'

    # ── SHARE /F:4096 /L:40 (second call) — already installed ─────────────────
    # INT 2Fh check: AL=0FFh → ShDispMsg prints "SHARE already installed"
    # then exits with errorlevel 255 (INT 21h/AH=4Ch/AL=0FFh inside ShDispMsg).
    printf 'ECHO ---SHARE-PARAMS---\r\n'
    printf 'SHARE /F:4096 /L:40\r\n'
    printf 'IF ERRORLEVEL 255 ECHO SHARE_ALREADY_EL\r\n'
    printf 'ECHO SHARE_PARAMS_DONE\r\n'

    # ── NLSFUNC (first call) — load NLS function TSR ─────────────────────────
    # No args → NO_PARMS=1 → installs silently via INT 2Fh + Keep_Process.
    # COUNTRY.SYS path not needed at install time.
    printf 'ECHO ---NLSFUNC---\r\n'
    printf 'NLSFUNC\r\n'
    printf 'ECHO NLSFUNC_DONE\r\n'

    # ── NLSFUNC C:\COUNTRY.SYS (second call) — already installed ──────────────
    # INT 2Fh/AH=MULT_NLSFUNC check: AL≠0 → "NLSFUNC already installed" +
    # exits with errorlevel 128 (ERROR_CODE=0x80).
    printf 'ECHO ---NLSFUNC-PATH---\r\n'
    printf 'NLSFUNC C:\COUNTRY.SYS\r\n'
    printf 'IF ERRORLEVEL 128 ECHO NLSFUNC_ALREADY_EL\r\n'
    printf 'ECHO NLSFUNC_PATH_DONE\r\n'

    # ── EXE2BIN TEST.EXE TEST.BIN — basic conversion ──────────────────────────
    # IP=0 → BINFIX path: no prompts, no output on success.
    # Verifiable via IF EXIST (EXE2BIN always exits errorlevel 0).
    printf 'ECHO ---EXE2BIN---\r\n'
    printf 'EXE2BIN TEST.EXE TEST.BIN\r\n'
    printf 'IF EXIST TEST.BIN ECHO EXE2BIN_FILE_OK\r\n'
    printf 'ECHO EXE2BIN_DONE\r\n'

    # ── EXE2BIN MISSING.EXE — file not found error ────────────────────────────
    # DosError path: INT 21h/AH=59h returns code 2 → extend_message prints
    # "File not found". EXE2BIN exits errorlevel 0 regardless.
    printf 'ECHO ---EXE2BIN-NOFILE---\r\n'
    printf 'EXE2BIN MISSING.EXE MISSING.BIN\r\n'
    printf 'ECHO EXE2BIN_NOFILE_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Step 2: boot QEMU ─────────────────────────────────────────────────────────
# No interactive prompts — continuous newline feed is unused but harmless.
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

# ── Check output ──────────────────────────────────────────────────────────────

echo ""
echo "--- SHARE tests ---"

if grep -q "SHARE_DONE" "$SERIAL_LOG"; then
    ok "SHARE (first call installed silently, batch continued)"
else
    fail "SHARE (batch hung or crashed after first SHARE call)"
fi

if grep -qi "SHARE already installed" "$SERIAL_LOG"; then
    ok "SHARE /F:4096 /L:40 (second call: 'SHARE already installed' message)"
else
    fail "SHARE /F:4096 /L:40 (expected 'SHARE already installed' on second call)"
fi

if grep -q "SHARE_ALREADY_EL" "$SERIAL_LOG"; then
    ok "SHARE /F:4096 /L:40 (second call: errorlevel 255 set)"
else
    fail "SHARE /F:4096 /L:40 (expected errorlevel 255 on already-installed)"
fi

if grep -q "SHARE_PARAMS_DONE" "$SERIAL_LOG"; then
    ok "SHARE /F:4096 /L:40 (batch continued after second call)"
else
    fail "SHARE /F:4096 /L:40 (batch hung or crashed)"
fi

echo ""
echo "--- NLSFUNC tests ---"

if grep -q "NLSFUNC_DONE" "$SERIAL_LOG"; then
    ok "NLSFUNC (first call installed silently, batch continued)"
else
    fail "NLSFUNC (batch hung or crashed after first NLSFUNC call)"
fi

# NOTE: NLSFUNC writes "NLSFUNC already installed" to STDERR (bx=STDERR in SYSDISPMSG),
# which is NOT redirected by CTTY AUX. We verify via errorlevel instead.
if grep -q "NLSFUNC_ALREADY_EL" "$SERIAL_LOG"; then
    ok "NLSFUNC C:\\COUNTRY.SYS (second call: errorlevel 128 — already installed)"
else
    fail "NLSFUNC C:\\COUNTRY.SYS (expected errorlevel 128 on second call)"
fi

if grep -q "NLSFUNC_PATH_DONE" "$SERIAL_LOG"; then
    ok "NLSFUNC C:\\COUNTRY.SYS (batch continued after second call)"
else
    fail "NLSFUNC C:\\COUNTRY.SYS (batch hung or crashed)"
fi

echo ""
echo "--- EXE2BIN tests ---"

if grep -q "EXE2BIN_FILE_OK" "$SERIAL_LOG"; then
    ok "EXE2BIN TEST.EXE TEST.BIN (output file TEST.BIN created)"
else
    fail "EXE2BIN TEST.EXE TEST.BIN (TEST.BIN not created — conversion failed)"
fi

if grep -q "EXE2BIN_DONE" "$SERIAL_LOG"; then
    ok "EXE2BIN TEST.EXE TEST.BIN (batch continued)"
else
    fail "EXE2BIN TEST.EXE TEST.BIN (batch hung or crashed)"
fi

if grep -qi "File not found" "$SERIAL_LOG"; then
    ok "EXE2BIN MISSING.EXE (printed 'File not found' for missing input)"
else
    fail "EXE2BIN MISSING.EXE (expected 'File not found' error message)"
fi

if grep -q "EXE2BIN_NOFILE_DONE" "$SERIAL_LOG"; then
    ok "EXE2BIN MISSING.EXE (batch continued after error)"
else
    fail "EXE2BIN MISSING.EXE (batch hung or crashed)"
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
