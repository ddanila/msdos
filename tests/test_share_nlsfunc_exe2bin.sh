#!/bin/bash
# tests/test_share_nlsfunc_exe2bin.sh — E2E tests for SHARE, NLSFUNC, EXE2BIN via QEMU.
#
# All three tools run in one QEMU boot. EXE2BIN's relocation path is driven
# through a private serial coordinator.
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
    printf 'CTTY AUX\r\n'

    # ── SHARE /NC (first call) — load file-sharing TSR with no-compat mode ────
    # /NC disables compatibility-mode checking (undocumented switch).
    # No output on success. Hooks INT 2Fh, calls INT 21h/31h (Keep_Process).
    printf 'ECHO ---SHARE---\r\n'
    printf 'SHARE /NC\r\n'
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

if grep -q "SHARE_DONE" "$SERIAL_LOG"; then
    ok "SHARE /NC (first call installed silently with no-compat mode, batch continued)"
else
    fail "SHARE /NC (batch hung or crashed after first SHARE call)"
fi

# NOTE: SHARE writes "SHARE already installed" via ShDispMsg which uses BIOS
# direct output, not through CTTY AUX — not capturable over serial.
# Verify via errorlevel instead (ShDispMsg exits with AL=0FFh = errorlevel 255).
if grep -q "SHARE_ALREADY_EL" "$SERIAL_LOG"; then
    ok "SHARE /F:4096 /L:40 (second call: errorlevel 255 — already installed)"
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
