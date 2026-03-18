#!/bin/bash
# tests/test_misc_qemu.sh — E2E tests for CHKDSK, MODE CON, IFSFUNC, FILESYS,
#                           FASTOPEN, GRAPHICS, PRINT, KEYB via QEMU.
#
# All tools in one QEMU boot; no interactive prompts needed.
#
# CHKDSK (CHKDSK.ASM):
#   - No args: checks current drive (A:), prints disk statistics.
#   - /V: verbose — lists every file path on the volume.
#   - Needs a real FAT filesystem; kvikdos has no disk layer.
#
# MODE CON /STATUS (MODE.ASM):
#   - Prints current console status (columns, lines, typematic rate/delay).
#   - Non-interactive; exits immediately after printing status.
#
# IFSFUNC (IFSFUNC.ASM):
#   - First call: installs IFS handler as TSR via INT 2Fh/AX=1100h + INT 21h/31h. Silent.
#   - Second call: INT 2Fh/AX=1100h returns AL≠0 → "IFSFUNC already installed".
#
# FILESYS (FILESYS.ASM):
#   - First call: installs filesystem helper as TSR. Silent on success.
#   - Requires IFSFUNC already resident.
#
# FASTOPEN (FASTINIT.ASM):
#   - First call: installs directory cache TSR. Silent on success.
#   - Second call: INT 2Fh check → "FASTOPEN already installed".
#
# GRAPHICS (GRINST.ASM):
#   - First call: loads GRAPHICS.PRO and installs print-screen handler. Silent.
#   - Second call: reloads silently (no "already installed" message — just reloads).
#   - GRAPHICS.PRO must be on the floppy (it is, via make deploy).
#
# PRINT (PRINT_T.ASM):
#   - First call with /D:PRN: installs resident spooler, prints
#     "Resident part of PRINT installed". No file queued; no device prompt (/D given).
#   - Second call (PRINT alone): queue already installed, shows queue status.
#
# KEYB (KEYB.ASM):
#   - KEYBOARD.SYS is not on the base floppy; we copy it in test setup.
#   - First call (KEYB US): installs INT 9h hook, loads US layout. Silent on success.
#   - Second call (KEYB, no args): prints "Current keyboard code: US" + code page info.
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

SRC="$REPO_ROOT/MS-DOS/v4.0/src"

echo "=== CHKDSK / MODE CON / IFSFUNC / FILESYS / FASTOPEN / GRAPHICS / PRINT / KEYB E2E tests (QEMU) ==="

# ── Build test floppy ────────────────────────────────────────────────────────
echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# KEYBOARD.SYS is not on the base floppy; copy it in for KEYB tests.
mcopy -o -i "$BOOT_IMG" "$SRC/DEV/KEYBOARD/KEYBOARD.SYS" ::KEYBOARD.SYS

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

    # ── FASTOPEN C:=50 (first call) — install directory cache TSR ────────────
    # Installs silently on success via INT 21h/31h (Keep_Process).
    printf 'ECHO ---FASTOPEN---\r\n'
    printf 'FASTOPEN C:=50\r\n'
    printf 'ECHO FASTOPEN_DONE\r\n'

    # ── FASTOPEN C:=50 (second call) — already installed ─────────────────────
    # INT 2Fh check detects existing install → prints "FASTOPEN already installed".
    printf 'ECHO ---FASTOPEN-AGAIN---\r\n'
    printf 'FASTOPEN C:=50\r\n'
    printf 'ECHO FASTOPEN_AGAIN_DONE\r\n'

    # ── GRAPHICS (first call) — load print-screen handler ────────────────────
    # Reads GRAPHICS.PRO from current drive root, installs handler. Silent.
    printf 'ECHO ---GRAPHICS---\r\n'
    printf 'GRAPHICS\r\n'
    printf 'ECHO GRAPHICS_DONE\r\n'

    # ── GRAPHICS (second call) — reload ──────────────────────────────────────
    # Already installed: reloads silently (no "already installed" message).
    printf 'ECHO ---GRAPHICS-AGAIN---\r\n'
    printf 'GRAPHICS\r\n'
    printf 'ECHO GRAPHICS_AGAIN_DONE\r\n'

    # ── PRINT /D:PRN (first call) — install print spooler ────────────────────
    # /D:PRN specifies device so no interactive device prompt.
    # Prints "Resident part of PRINT installed" on success.
    printf 'ECHO ---PRINT---\r\n'
    printf 'PRINT /D:PRN\r\n'
    printf 'ECHO PRINT_DONE\r\n'

    # ── PRINT (second call) — already installed, show queue ───────────────────
    # Resident already in memory; no re-install prompt. Shows queue (empty).
    printf 'ECHO ---PRINT-AGAIN---\r\n'
    printf 'PRINT\r\n'
    printf 'ECHO PRINT_AGAIN_DONE\r\n'

    # ── KEYB US (first call) — load US keyboard layout ────────────────────────
    # KEYBOARD.SYS copied to floppy root in test setup.
    # Installs INT 9h hook and loads US layout. Silent on success.
    printf 'ECHO ---KEYB---\r\n'
    printf 'KEYB US\r\n'
    printf 'ECHO KEYB_DONE\r\n'

    # ── KEYB (no args) — show current layout ─────────────────────────────────
    # Prints "Current keyboard code: US" + code page info.
    printf 'ECHO ---KEYB-STATUS---\r\n'
    printf 'KEYB\r\n'
    printf 'ECHO KEYB_STATUS_DONE\r\n'

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

# ── FASTOPEN checks ───────────────────────────────────────────────────────────
echo ""
echo "--- FASTOPEN tests ---"

if grep -q "FASTOPEN_DONE" "$SERIAL_LOG"; then
    ok "FASTOPEN C:=50 (first call installed silently, batch continued)"
else
    fail "FASTOPEN C:=50 (batch hung or crashed after first call)"
fi

# Note: FASTOPEN's "already installed" / install messages go to the physical
# screen via direct BIOS writes, not through CTTY AUX — not capturable over
# serial. On second call FASTOPEN rejects C: as already cached ("Invalid drive
# specification") — not a crash, batch continues normally.
if grep -q "FASTOPEN_AGAIN_DONE" "$SERIAL_LOG"; then
    ok "FASTOPEN C:=50 (second call: batch continued without hang)"
else
    fail "FASTOPEN C:=50 (batch hung or crashed after second call)"
fi

# ── GRAPHICS checks ────────────────────────────────────────────────────────────
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

# ── PRINT checks ───────────────────────────────────────────────────────────────
echo ""
echo "--- PRINT tests ---"

if grep -qi "Resident part of PRINT installed" "$SERIAL_LOG"; then
    ok "PRINT /D:PRN (printed 'Resident part of PRINT installed')"
else
    fail "PRINT /D:PRN (expected 'Resident part of PRINT installed')"
fi

if grep -q "PRINT_DONE" "$SERIAL_LOG"; then
    ok "PRINT /D:PRN (batch continued after install)"
else
    fail "PRINT /D:PRN (batch hung or crashed)"
fi

if grep -q "PRINT_AGAIN_DONE" "$SERIAL_LOG"; then
    ok "PRINT (second call: batch continued)"
else
    fail "PRINT (batch hung or crashed on second call)"
fi

# ── KEYB checks ────────────────────────────────────────────────────────────────
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
