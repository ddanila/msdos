#!/bin/bash
# tests/test_share_nlsfunc_exe2bin.sh — E2E tests for SHARE, NLSFUNC, EXE2BIN via QEMU.
#
# All three tools run in one QEMU boot. EXE2BIN's relocation path is driven
# through a private serial coordinator.
#
# SHARE (GSHARE2.ASM):
#   - First call: installs as TSR (INT 2Fh hook + INT 21h/31h Keep_Process). No output.
#   - A call without /NC toggles compatibility checking back on; the following
#     same-mode call returns AL=0FFh and prints
#     "SHARE already installed" (COMMON2: "%1 already installed") → exits with AL=0FFh
#     (errorlevel 255) via ShDispMsg's INT 21h/AH=4Ch.
#
# NLSFUNC (NLSFUNC.ASM):
#   - First call (no args): NO_PARMS=1 → installs via INT 2Fh hook + INT 21h/31h. No output.
#   - Second no-argument call: INT 2Fh/AH=MULT_NLSFUNC returns installed →
#     prints "NLSFUNC already installed" (COMMON2) + ERROR_CODE=80 decimal
#     (errorlevel 80 decimal) via INT 21h/AH=4Ch.
#   - A supplied COUNTRY.SYS path is opened before the installed-state check.
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
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

BOOT_IMG="$OUT/floppy-share-nlsfunc-boot.img"
SERIAL_LOG="$OUT/share-nlsfunc-serial.log"
SERIAL_IN="$OUT/share-nlsfunc-serial.in"
SERIAL_OUT="$OUT/share-nlsfunc-serial.out"
EXIT_COM="$OUT/share-nlsfunc-qexit.com"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'kill ${QEMU_PID:-} 2>/dev/null; rm -f "$SERIAL_IN" "$SERIAL_OUT" 2>/dev/null; true' EXIT

echo "=== SHARE / NLSFUNC / EXE2BIN E2E tests (QEMU) ==="

# ── Step 1: build boot floppy ────────────────────────────────────────────────
echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# Minimal valid EXE for EXE2BIN conversion test. This implementation rounds the
# declared header paragraphs to a 512-byte boundary when computing load size,
# so fixtures use a 512-byte header (e_cparhdr=20h), not merely the 28-byte MZ
# structure.
# e_ip=0 → BINFIX path in EXE2BIN (binary conversion, no "Fix-ups needed" prompt).
# e_crlc=0 → no relocations → no segment prompt.
# e_cp=2, e_cblp=1 → total file = 513 bytes (512 header + 1 byte code).
# Code = 0xC3 (RET) — any single byte works; EXE2BIN just copies it verbatim.
#
# Offsets: MZ(0) cblp(2) cp(4) crlc(6) cparhdr(8) minalloc(10) maxalloc(12)
#          ss(14) sp(16) csum(18) ip(20) cs(22) lfarlc(24) ovno(26)
{
    printf '\115\132\001\000\002\000\000\000\040\000\000\000\377\377\000\000\000\000\000\000\000\000\000\000\034\000\000\000\000\000\000\000'
    dd if=/dev/zero bs=480 count=1 status=none
    printf '\303'
} | mcopy -o -i "$BOOT_IMG" - ::TEST.EXE

# COM-path fixture: IP=100h and no relocations. EXE2BIN must discard the first
# 100h bytes of the load image and emit only the final C3 payload byte.
{
    printf '\115\132\001\001\002\000\000\000\040\000\000\000\377\377\000\000\000\000\000\000\000\001\000\000\034\000\000\000\000\000\000\000'
    dd if=/dev/zero bs=480 count=1 status=none
    dd if=/dev/zero bs=256 count=1 status=none
    printf '\303'
} | mcopy -o -i "$BOOT_IMG" - ::COMPATH.EXE

# Relocation fixture: one relocation entry at header offset 1Ch points at the
# first load word (1234h). A supplied base segment of 0010h must produce 1244h.
{
    printf '\115\132\002\000\002\000\001\000\040\000\000\000\377\377\000\000\000\000\000\000\000\000\000\000\034\000\000\000\000\000\000\000'
    dd if=/dev/zero bs=480 count=1 status=none
    printf '\064\022'
} | mcopy -o -i "$BOOT_IMG" - ::RELOC.EXE

# Three independent structural rejection fixtures: bad MZ signature, nonzero
# initial SS, and an IP that is neither BIN (0) nor COM (100h).
printf 'NOT_AN_MZ_EXECUTABLE' | mcopy -o -i "$BOOT_IMG" - ::BADSIG.EXE
{
    printf '\115\132\001\000\002\000\000\000\040\000\000\000\377\377\001\000\000\000\000\000\000\000\000\000\034\000\000\000\000\000\000\000'
    dd if=/dev/zero bs=480 count=1 status=none
    printf '\303'
} | mcopy -o -i "$BOOT_IMG" - ::BADSS.EXE
{
    printf '\115\132\001\000\002\000\000\000\040\000\000\000\377\377\000\000\000\000\000\000\001\000\000\000\034\000\000\000\000\000\000\000'
    dd if=/dev/zero bs=480 count=1 status=none
    printf '\303'
} | mcopy -o -i "$BOOT_IMG" - ::BADIP.EXE

nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'

    # ── SHARE /NC /F /L (first call) — load with every parser switch ─────────
    # /NC disables compatibility checking; /F and /L size the file and lock tables.
    # No output on success. Hooks INT 2Fh, calls INT 21h/31h (Keep_Process).
    printf 'ECHO ---SHARE---\r\n'
    printf 'SHARE /F:0\r\n'
    printf 'ECHO SHARE_F_LOW_DONE\r\n'
    printf 'SHARE /F:65536\r\n'
    printf 'ECHO SHARE_F_HIGH_DONE\r\n'
    printf 'SHARE /L:0\r\n'
    printf 'ECHO SHARE_L_LOW_DONE\r\n'
    printf 'SHARE /L:65536\r\n'
    printf 'ECHO SHARE_L_HIGH_DONE\r\n'
    printf 'SHARE /X\r\n'
    printf 'ECHO SHARE_UNKNOWN_DONE\r\n'
    printf 'SHARE FILE\r\n'
    printf 'ECHO SHARE_POSITIONAL_DONE\r\n'
    printf 'SHARE /NC /F:4096 /L:40\r\n'
    printf 'ECHO SHARE_DONE\r\n'

    # Omitting /NC first toggles compatibility checking back on with a quiet
    # return; repeating that mode then reaches the already-installed result.
    printf 'ECHO ---SHARE-PARAMS---\r\n'
    printf 'SHARE /F:4096 /L:40\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SHARE_TOGGLE_FAILED\r\n'
    printf 'SHARE /F:4096 /L:40\r\n'
    printf 'IF ERRORLEVEL 255 ECHO SHARE_ALREADY_EL\r\n'
    printf 'ECHO SHARE_PARAMS_DONE\r\n'

    # ── NLSFUNC (first call) — load NLS function TSR ─────────────────────────
    # No args → NO_PARMS=1 → installs silently via INT 2Fh + Keep_Process.
    # COUNTRY.SYS path not needed at install time.
    printf 'ECHO ---NLSFUNC---\r\n'
    printf 'NLSFUNC /X\r\n'
    printf 'ECHO NLSFUNC_UNKNOWN_DONE\r\n'
    printf 'NLSFUNC A B\r\n'
    printf 'ECHO NLSFUNC_EXCESS_DONE\r\n'
    printf 'NLSFUNC\r\n'
    printf 'ECHO NLSFUNC_DONE\r\n'

    printf 'NLSFUNC\r\n'
    printf 'IF ERRORLEVEL 80 ECHO NLSFUNC_ALREADY_EL\r\n'

    # A named path is opened before the installed-state check, so a missing
    # COUNTRY.SYS must retain its DOS file-not-found result even after install.
    printf 'ECHO ---NLSFUNC-PATH---\r\n'
    printf 'NLSFUNC C:\COUNTRY.SYS\r\n'
    printf 'IF ERRORLEVEL 3 ECHO NLSFUNC_PATH_TOO_HIGH\r\n'
    printf 'IF ERRORLEVEL 2 ECHO NLSFUNC_PATH_EL2\r\n'
    printf 'ECHO NLSFUNC_PATH_DONE\r\n'

    # ── EXE2BIN TEST.EXE TEST.BIN — basic conversion ──────────────────────────
    # IP=0 → BINFIX path: no prompts, no output on success.
    # Verifiable via IF EXIST (EXE2BIN always exits errorlevel 0).
    printf 'ECHO ---EXE2BIN---\r\n'
    printf 'EXE2BIN\r\n'
    printf 'ECHO EXE2BIN_MISSING_DONE\r\n'
    printf 'EXE2BIN A B C\r\n'
    printf 'ECHO EXE2BIN_EXCESS_DONE\r\n'
    printf 'EXE2BIN TEST.EXE TEST.BIN\r\n'
    printf 'IF EXIST TEST.BIN ECHO EXE2BIN_FILE_OK\r\n'
    printf 'ECHO EXE2BIN_DONE\r\n'

    printf 'ECHO ---EXE2BIN-COM---\r\n'
    printf 'EXE2BIN COMPATH.EXE COMPATH.COM\r\n'
    printf 'IF EXIST COMPATH.COM ECHO EXE2BIN_COM_FILE_OK\r\n'

    printf 'ECHO ---EXE2BIN-RELOC---\r\n'
    printf 'EXE2BIN RELOC.EXE RELOC.BIN\r\n'
    printf 'IF EXIST RELOC.BIN ECHO EXE2BIN_RELOC_FILE_OK\r\n'

    printf 'ECHO ---EXE2BIN-INVALID---\r\n'
    printf 'EXE2BIN BADSIG.EXE BADSIG.BIN\r\n'
    printf 'EXE2BIN BADSS.EXE BADSS.BIN\r\n'
    printf 'EXE2BIN BADIP.EXE BADIP.BIN\r\n'
    printf 'IF NOT EXIST BADSIG.BIN ECHO EXE2BIN_BADSIG_NO_OUTPUT\r\n'
    printf 'IF NOT EXIST BADSS.BIN ECHO EXE2BIN_BADSS_NO_OUTPUT\r\n'
    printf 'IF NOT EXIST BADIP.BIN ECHO EXE2BIN_BADIP_NO_OUTPUT\r\n'

    # ── EXE2BIN MISSING.EXE — file not found error ────────────────────────────
    # DosError path: INT 21h/AH=59h returns code 2 → extend_message prints
    # "File not found". EXE2BIN exits errorlevel 0 regardless.
    printf 'ECHO ---EXE2BIN-NOFILE---\r\n'
    printf 'EXE2BIN MISSING.EXE MISSING.BIN\r\n'
    printf 'ECHO EXE2BIN_NOFILE_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Step 2: boot QEMU ─────────────────────────────────────────────────────────
echo "Booting QEMU..."
rm -f "$SERIAL_LOG" "$SERIAL_IN" "$SERIAL_OUT"
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"
timeout 30 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -m 4 \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -serial pipe:"$OUT/share-nlsfunc-serial" \
    2>/dev/null &
QEMU_PID=$!

python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$SERIAL_LOG" \
    'Fix-ups needed - base segment (hex):' '0010\r'

wait "$QEMU_PID" || true
exec 3>&-

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

# ── Check output ──────────────────────────────────────────────────────────────

echo ""
echo "--- SHARE tests ---"

share_rejections_complete=1
for diagnostic in \
    'Parameter value not in allowed range -  /F:0' \
    'Parameter value not in allowed range -  /F:65536' \
    'Parameter value not in allowed range -  /L:0' \
    'Parameter value not in allowed range -  /L:65536' \
    'Invalid switch -  /X' \
    'Parameter format not correct -  FILE'; do
    grep -Fq -- "$diagnostic" "$SERIAL_LOG" || share_rejections_complete=0
done
if [[ $share_rejections_complete -eq 1 ]] \
    && grep -q 'SHARE_F_LOW_DONE' "$SERIAL_LOG" \
    && grep -q 'SHARE_F_HIGH_DONE' "$SERIAL_LOG" \
    && grep -q 'SHARE_L_LOW_DONE' "$SERIAL_LOG" \
    && grep -q 'SHARE_L_HIGH_DONE' "$SERIAL_LOG" \
    && grep -q 'SHARE_UNKNOWN_DONE' "$SERIAL_LOG" \
    && grep -q 'SHARE_POSITIONAL_DONE' "$SERIAL_LOG"; then
    ok "SHARE rejects numeric boundaries, unknown switches, and positional operands"
else
    fail "SHARE parser rejection contracts"
fi

if grep -q "SHARE_DONE" "$SERIAL_LOG"; then
    ok "SHARE /NC /F:4096 /L:40 (all switches installed, batch continued)"
else
    fail "SHARE /NC /F:4096 /L:40 (batch hung or crashed after first SHARE call)"
fi

# NOTE: SHARE writes "SHARE already installed" via ShDispMsg which uses BIOS
# direct output, not through CTTY AUX — not capturable over serial.
# Verify via errorlevel instead (ShDispMsg exits with AL=0FFh = errorlevel 255).
if grep -q "SHARE_ALREADY_EL" "$SERIAL_LOG" \
    && ! grep -q 'SHARE_TOGGLE_FAILED' "$SERIAL_LOG"; then
    ok "SHARE /NC-to-full transition precedes errorlevel 255 already-installed state"
else
    fail "SHARE compatibility-mode transition and already-installed contract"
fi

if grep -q "SHARE_PARAMS_DONE" "$SERIAL_LOG"; then
    ok "SHARE batch continued after compatibility-state checks"
else
    fail "SHARE /F:4096 /L:40 (batch hung or crashed)"
fi

echo ""
echo "--- NLSFUNC tests ---"

if grep -q 'Invalid switch -  /X' "$SERIAL_LOG" \
    && grep -q 'NLSFUNC_UNKNOWN_DONE' "$SERIAL_LOG"; then
    ok "NLSFUNC rejects an unknown switch and returns to the batch"
else
    fail "NLSFUNC unknown-switch parser contract"
fi

if grep -q 'Too many parameters - B' "$SERIAL_LOG" \
    && grep -q 'NLSFUNC_EXCESS_DONE' "$SERIAL_LOG"; then
    ok "NLSFUNC rejects a second positional operand and returns"
else
    fail "NLSFUNC excess-operand parser contract"
fi

if grep -q "NLSFUNC_DONE" "$SERIAL_LOG"; then
    ok "NLSFUNC (first call installed silently, batch continued)"
else
    fail "NLSFUNC (batch hung or crashed after first NLSFUNC call)"
fi

# NLSFUNC's source assigns decimal 80 (not 80h) to the installed error code.
if grep -q "NLSFUNC_ALREADY_EL" "$SERIAL_LOG"; then
    ok "NLSFUNC second installation reports errorlevel 80"
else
    fail "NLSFUNC second-installation contract"
fi

if grep -Fq 'File not found - C:\COUNTRY.SYS' "$SERIAL_LOG" \
    && grep -q 'NLSFUNC_PATH_EL2' "$SERIAL_LOG" \
    && ! grep -q 'NLSFUNC_PATH_TOO_HIGH' "$SERIAL_LOG" \
    && grep -q "NLSFUNC_PATH_DONE" "$SERIAL_LOG"; then
    ok "NLSFUNC missing named path preserves errorlevel 2 after installation"
else
    fail "NLSFUNC installed-state path-error precedence contract"
fi

echo ""
echo "--- EXE2BIN tests ---"

if grep -q 'Required parameter missing -' "$SERIAL_LOG" \
    && grep -q 'EXE2BIN_MISSING_DONE' "$SERIAL_LOG"; then
    ok "EXE2BIN rejects a missing required input operand"
else
    fail "EXE2BIN missing-operand parser contract"
fi

if grep -q 'Too many parameters - C' "$SERIAL_LOG" \
    && grep -q 'EXE2BIN_EXCESS_DONE' "$SERIAL_LOG"; then
    ok "EXE2BIN rejects a third positional operand"
else
    fail "EXE2BIN excess-operand parser contract"
fi

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

basic_bytes=$(mcopy -i "$BOOT_IMG" ::TEST.BIN - 2>/dev/null | od -An -tx1 | tr -d ' \n')
if [[ "$basic_bytes" == "c3" ]]; then
    ok "EXE2BIN BIN path emitted the exact payload byte"
else
    fail "EXE2BIN BIN path emitted unexpected bytes: $basic_bytes"
fi

com_bytes=$(mcopy -i "$BOOT_IMG" ::COMPATH.COM - 2>/dev/null | od -An -tx1 | tr -d ' \n')
if grep -q "EXE2BIN_COM_FILE_OK" "$SERIAL_LOG" && [[ "$com_bytes" == "c3" ]]; then
    ok "EXE2BIN COM path stripped the initial 100h bytes exactly"
else
    fail "EXE2BIN COM path output mismatch: $com_bytes"
fi

reloc_bytes=$(mcopy -i "$BOOT_IMG" ::RELOC.BIN - 2>/dev/null | od -An -tx1 | tr -d ' \n')
if grep -q "EXE2BIN_RELOC_FILE_OK" "$SERIAL_LOG" && [[ "$reloc_bytes" == "4412" ]]; then
    ok "EXE2BIN relocation path added base segment 0010h to word 1234h"
else
    fail "EXE2BIN relocation output mismatch: $reloc_bytes"
fi

cannot_convert_count=$(grep -ci "File cannot be converted" "$SERIAL_LOG" || true)
if [[ "$cannot_convert_count" -eq 3 ]] &&
   grep -q "EXE2BIN_BADSIG_NO_OUTPUT" "$SERIAL_LOG" &&
   grep -q "EXE2BIN_BADSS_NO_OUTPUT" "$SERIAL_LOG" &&
   grep -q "EXE2BIN_BADIP_NO_OUTPUT" "$SERIAL_LOG"; then
    ok "EXE2BIN rejected bad signature, nonzero SS, and invalid IP without outputs"
else
    fail "EXE2BIN structural rejection contracts were not all observed"
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
