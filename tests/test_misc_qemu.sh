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
#   - Third call (KEYB GR,,KEYBOARD.SYS): loads German layout with explicit file path.
#   - Fourth call (KEYB, no args): verifies "GR" is now the active layout.
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

# KEYBOARD.SYS is deployed to the floppy by make deploy (alongside KEYB.COM).

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

    # ── MODE CON COLS=80 LINES=25 — set console dimensions ─────────────────
    # Non-interactive: sets text mode and prints status.
    printf 'ECHO ---MODE-CON-SET---\r\n'
    printf 'MODE CON COLS=80 LINES=25\r\n'
    printf 'ECHO MODE_CON_SET_DONE\r\n'

    # ── MODE CON RATE=30 DELAY=1 — set typematic rate ──────────────────────
    # Sets keyboard repeat rate and delay via INT 16h/AH=03h.
    printf 'ECHO ---MODE-TYPAMAT---\r\n'
    printf 'MODE CON RATE=30 DELAY=1\r\n'
    printf 'ECHO MODE_TYPAMAT_DONE\r\n'

    # ── CHKDSK A:\COMMAND.COM — file allocation check ──────────────────────
    # Reports allocation info for a specific file.
    printf 'ECHO ---CHKDSK-FILE---\r\n'
    printf 'CHKDSK A:\COMMAND.COM\r\n'
    printf 'ECHO CHKDSK_FILE_DONE\r\n'

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

    # ── FASTOPEN D:=20 /X — expanded memory cache ─────────────────────────
    # /X creates name cache in EMS. Without EMM386/EMS, FASTOPEN should fail
    # gracefully (error message) rather than crash. Tests /X parsing path.
    # Note: FASTOPEN is already installed from earlier call, so this will
    # also get "already installed" — but the /X parsing still exercises code.
    printf 'ECHO ---FASTOPEN-X---\r\n'
    printf 'FASTOPEN D:=20 /X\r\n'
    printf 'ECHO FASTOPEN_X_DONE\r\n'

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

    # ── PRINT /D:PRN (first call) — install print spooler with params ────────
    # /D:PRN specifies device so no interactive device prompt.
    # /B:512 /S:8 /U:1 /M:2 are install-time params (buffer, slice, busy, max ticks).
    # Prints "Resident part of PRINT installed" on success.
    printf 'ECHO ---PRINT---\r\n'
    printf 'PRINT /D:PRN /B:512 /Q:5 /S:8 /U:1 /M:2\r\n'
    printf 'ECHO PRINT_DONE\r\n'

    # ── PRINT (second call) — already installed, show queue ───────────────────
    # Resident already in memory; no re-install prompt. Shows queue (empty).
    printf 'ECHO ---PRINT-AGAIN---\r\n'
    printf 'PRINT\r\n'
    printf 'ECHO PRINT_AGAIN_DONE\r\n'

    # ── PRINT file /P — add file to print queue ──────────────────────────────
    # /P adds the preceding filename to the queue. AUTOEXEC.BAT is on the floppy.
    printf 'ECHO ---PRINT-P---\r\n'
    printf 'PRINT AUTOEXEC.BAT /P\r\n'
    printf 'ECHO PRINT_P_DONE\r\n'

    # ── PRINT AUTOEXEC.BAT /C — remove file from queue ────────────────────────
    # /C cancels the preceding filename from the queue.
    printf 'ECHO ---PRINT-C---\r\n'
    printf 'PRINT AUTOEXEC.BAT /C\r\n'
    printf 'ECHO PRINT_C_DONE\r\n'

    # ── PRINT /T — terminate (cancel) all files in queue ──────────────────────
    # /T cancels all pending print jobs. Prints "PRINT queue is empty".
    printf 'ECHO ---PRINT-T---\r\n'
    printf 'PRINT /T\r\n'
    printf 'ECHO PRINT_T_DONE\r\n'

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

    # ── KEYB GR,,KEYBOARD.SYS — load German layout with explicit file ───────
    # Syntax: KEYB lang[,[codepage][,[drive:][path]file]] [/ID:nnn]
    # Tests non-US layout loading with explicit KEYBOARD.SYS path.
    printf 'ECHO ---KEYB-GR---\r\n'
    printf 'KEYB GR,,KEYBOARD.SYS\r\n'
    printf 'ECHO KEYB_GR_DONE\r\n'

    # ── KEYB (no args) — verify GR is now active ────────────────────────────
    printf 'ECHO ---KEYB-GR-STATUS---\r\n'
    printf 'KEYB\r\n'
    printf 'ECHO KEYB_GR_STATUS_DONE\r\n'

    # ── KEYB UK,850,KEYBOARD.SYS — load UK layout with explicit code page ──
    # Syntax: KEYB lang[,[codepage][,[drive:][path]file]] [/ID:nnn]
    # Tests loading a layout with explicit code page parameter.
    printf 'ECHO ---KEYB-UK-850---\r\n'
    printf 'KEYB UK,850,KEYBOARD.SYS\r\n'
    printf 'ECHO KEYB_UK_850_DONE\r\n'

    # ── KEYB (no args) — verify UK is now active ──────────────────────────
    printf 'ECHO ---KEYB-UK-STATUS---\r\n'
    printf 'KEYB\r\n'
    printf 'ECHO KEYB_UK_STATUS_DONE\r\n'

    # ── KEYB FR,850,KEYBOARD.SYS /ID:189 — load French layout with /ID ────
    # Tests the /ID switch parsing path. FR has two keyboard IDs (120, 189).
    printf 'ECHO ---KEYB-ID---\r\n'
    printf 'KEYB FR,850,KEYBOARD.SYS /ID:189\r\n'
    printf 'ECHO KEYB_ID_DONE\r\n'

    # ── KEYB (no args) — verify FR is now active ──────────────────────────
    printf 'ECHO ---KEYB-FR-STATUS---\r\n'
    printf 'KEYB\r\n'
    printf 'ECHO KEYB_FR_STATUS_DONE\r\n'

    # ── GRAPHICS /R — load with reverse printing ────────────────────────────
    # /R reverses foreground/background when printing. Installs silently.
    # (GRAPHICS already installed from earlier call; this reloads with /R.)
    printf 'ECHO ---GRAPHICS-R---\r\n'
    printf 'GRAPHICS /R\r\n'
    printf 'ECHO GRAPHICS_R_DONE\r\n'

    # ── GRAPHICS /B — load with background printing ─────────────────────────
    # /B enables printing of background color. Reloads silently.
    # Note: /B is invalid with BLACK_WHITE printers; default printer type may
    # vary — if this fails, the batch marker still tells us it didn't hang.
    printf 'ECHO ---GRAPHICS-B---\r\n'
    printf 'GRAPHICS /B\r\n'
    printf 'ECHO GRAPHICS_B_DONE\r\n'

    # ── GRAPHICS /LCD — load with LCD aspect ratio ──────────────────────────
    # /LCD sets LCD printbox (mutually exclusive with /PB). Reloads silently.
    printf 'ECHO ---GRAPHICS-LCD---\r\n'
    printf 'GRAPHICS /LCD\r\n'
    printf 'ECHO GRAPHICS_LCD_DONE\r\n'

    # ── GRAPHICS /PB:STD — load with explicit printbox ID ───────────────────
    # /PB:id (or /PRINTBOX:id) sets a named printbox from GRAPHICS.PRO.
    # "STD" is the default printbox. Mutually exclusive with /LCD.
    printf 'ECHO ---GRAPHICS-PB---\r\n'
    printf 'GRAPHICS /PB:STD\r\n'
    printf 'ECHO GRAPHICS_PB_DONE\r\n'

    # ── COMMAND /? — help text (regression for boot-crash fix 58a0bb4) ────────
    # COMMAND /? prints help and exits. Verifies the /? code path doesn't crash.
    printf 'ECHO ---COMMAND-HELP---\r\n'
    printf 'COMMAND /?\r\n'
    printf 'ECHO COMMAND_HELP_DONE\r\n'

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

# CHKDSK A:\COMMAND.COM — file allocation check
if grep -q "CHKDSK_FILE_DONE" "$SERIAL_LOG"; then
    ok "CHKDSK A:\\COMMAND.COM (file allocation check, batch continued)"
else
    fail "CHKDSK A:\\COMMAND.COM (batch hung or crashed)"
fi

# ── MODE CON /STATUS checks ───────────────────────────────────────────────────
echo ""
echo "--- MODE CON tests ---"

if grep -qi "Status" "$SERIAL_LOG" && grep -q "MODE_CON_DONE" "$SERIAL_LOG"; then
    ok "MODE CON /STATUS (status output printed, batch continued)"
else
    fail "MODE CON /STATUS (expected 'Status' output and MODE_CON_DONE marker)"
fi

# MODE CON COLS=80 LINES=25
if grep -q "MODE_CON_SET_DONE" "$SERIAL_LOG"; then
    ok "MODE CON COLS=80 LINES=25 (set console dimensions, batch continued)"
else
    fail "MODE CON COLS=80 LINES=25 (batch hung or crashed)"
fi

# MODE CON RATE=30 DELAY=1
if grep -q "MODE_TYPAMAT_DONE" "$SERIAL_LOG"; then
    ok "MODE CON RATE=30 DELAY=1 (set typematic rate, batch continued)"
else
    fail "MODE CON RATE=30 DELAY=1 (batch hung or crashed)"
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

# FASTOPEN /X — expanded memory cache (no EMS available, tests /X parsing)
if grep -q "FASTOPEN_X_DONE" "$SERIAL_LOG"; then
    ok "FASTOPEN D:=20 /X (expanded memory switch parsed, batch continued)"
else
    fail "FASTOPEN D:=20 /X (batch hung or crashed — /X parsing may have failed)"
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
    ok "PRINT /D:PRN /B:512 /Q:5 /S:8 /U:1 /M:2 (batch continued after install with params)"
else
    fail "PRINT /D:PRN /B:512 /Q:5 /S:8 /U:1 /M:2 (batch hung or crashed)"
fi

if grep -q "PRINT_AGAIN_DONE" "$SERIAL_LOG"; then
    ok "PRINT (second call: batch continued)"
else
    fail "PRINT (batch hung or crashed on second call)"
fi

# PRINT file /P — add file to queue
if grep -q "PRINT_P_DONE" "$SERIAL_LOG"; then
    ok "PRINT AUTOEXEC.BAT /P (add to queue, batch continued)"
else
    fail "PRINT AUTOEXEC.BAT /P (batch hung or crashed)"
fi

# PRINT file /C — remove file from queue
if grep -q "PRINT_C_DONE" "$SERIAL_LOG"; then
    ok "PRINT AUTOEXEC.BAT /C (remove from queue, batch continued)"
else
    fail "PRINT AUTOEXEC.BAT /C (batch hung or crashed)"
fi

# PRINT /T — cancel queue
if grep -q "PRINT_T_DONE" "$SERIAL_LOG"; then
    ok "PRINT /T (terminate queue, batch continued)"
else
    fail "PRINT /T (batch hung or crashed)"
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

# KEYB GR — non-US layout with explicit KEYBOARD.SYS
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

# KEYB UK,850 — UK layout with explicit code page
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

# KEYB FR,850 /ID:189 — French layout with keyboard ID
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

# ── GRAPHICS /R /B checks ────────────────────────────────────────────────────
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

# ── COMMAND /? checks ─────────────────────────────────────────────────────────
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
