#!/bin/bash
# tests/test_misc_qemu.sh — E2E tests for CHKDSK, MODE CON, IFSFUNC, FILESYS via QEMU.
#
# All four tools in one QEMU boot; no interactive prompts needed.
#
# CHKDSK (CHKDSK.ASM):
#   - No args: checks current drive (A:), prints disk statistics and memory summary.
#   - /V: verbose — lists every file path on the volume.
#   - Needs a real FAT filesystem; kvikdos has no disk layer.
#
# MODE CON /STATUS (MODE.ASM):
#   - Prints current console status (columns, lines, typematic rate/delay).
#   - Non-interactive; output captured over serial.
#
# IFSFUNC (IFSFUNC.ASM):
#   - First call: installs IFS handler as TSR via INT 2Fh/AX=1100h + INT 21h/31h. Silent.
#   - Second call: INT 2Fh/AX=1100h check returns AL≠0 (already loaded) →
#     prints "IFSFUNC already installed" then exits.
#
# FILESYS (FILESYS.ASM):
#   - First call: installs filesystem helper as TSR. Silent on success.
#   - Requires IFSFUNC to already be resident (INT 2Fh/AX=1100h must be hooked).
#
# Run via: make test-misc-qemu  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/floppy-misc-qemu.img"
SERIAL_LOG="$OUT/misc-qemu-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== CHKDSK / MODE CON / IFSFUNC / FILESYS E2E tests (QEMU) ==="

# ── Build test floppy ────────────────────────────────────────────────────────
echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

{
    printf 'CTTY AUX\r\n'

    # ── CHKDSK — disk statistics ──────────────────────────────────────────────
    # No args checks current drive (A:). Prints "X bytes total disk space" and
    # "X bytes available on disk" plus a memory summary.
    printf 'ECHO ---CHKDSK---\r\n'
    printf 'CHKDSK\r\n'
    printf 'ECHO CHKDSK_DONE\r\n'

    # ── CHKDSK /V — verbose file listing ─────────────────────────────────────
    # Lists every file on the volume with its full path (e.g. A:\COMMAND.COM).
    printf 'ECHO ---CHKDSK-V---\r\n'
    printf 'CHKDSK /V\r\n'
    printf 'ECHO CHKDSK_V_DONE\r\n'

    # ── MODE CON /STATUS — console status ────────────────────────────────────
    # Prints current console columns, lines, and typematic settings.
    # Non-interactive; exits immediately after printing status.
    printf 'ECHO ---MODE-CON---\r\n'
    printf 'MODE CON /STATUS\r\n'
    printf 'ECHO MODE_CON_DONE\r\n'

    # ── IFSFUNC (first call) — install IFS handler ────────────────────────────
    # INT 2Fh/AX=1100h not yet hooked → installs via INT 21h/31h. No output.
    printf 'ECHO ---IFSFUNC---\r\n'
    printf 'IFSFUNC\r\n'
    printf 'ECHO IFSFUNC_DONE\r\n'

    # ── IFSFUNC (second call) — already installed ─────────────────────────────
    # INT 2Fh/AX=1100h returns AL≠0 → prints "IFSFUNC already installed".
    printf 'ECHO ---IFSFUNC-AGAIN---\r\n'
    printf 'IFSFUNC\r\n'
    printf 'ECHO IFSFUNC_AGAIN_DONE\r\n'

    # ── FILESYS — install filesystem helper ───────────────────────────────────
    # Requires IFSFUNC already resident. Installs silently via INT 21h/31h.
    printf 'ECHO ---FILESYS---\r\n'
    printf 'FILESYS\r\n'
    printf 'ECHO FILESYS_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Boot QEMU and capture serial output ──────────────────────────────────────
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

# ── CHKDSK checks ─────────────────────────────────────────────────────────────
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

# ── MODE CON /STATUS checks ───────────────────────────────────────────────────
echo ""
echo "--- MODE CON /STATUS tests ---"

if grep -qi "Status" "$SERIAL_LOG" && grep -q "MODE_CON_DONE" "$SERIAL_LOG"; then
    ok "MODE CON /STATUS (status output printed, batch continued)"
else
    fail "MODE CON /STATUS (expected 'Status' output and MODE_CON_DONE marker)"
fi

# ── IFSFUNC checks ────────────────────────────────────────────────────────────
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

# ── FILESYS checks ────────────────────────────────────────────────────────────
echo ""
echo "--- FILESYS tests ---"

if grep -q "FILESYS_DONE" "$SERIAL_LOG"; then
    ok "FILESYS (installed silently, batch continued)"
else
    fail "FILESYS (batch hung or crashed)"
fi

# ── Completion check ──────────────────────────────────────────────────────────
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
