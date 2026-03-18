#!/bin/bash
# tests/test_assign_subst_join.sh — E2E tests for ASSIGN, SUBST, and JOIN via QEMU.
#
# All three are TSR-based drive-manipulation tools that cannot run under kvikdos
# (kvikdos has no disk layer / drive table).  One QEMU boot covers all three.
#
# ASSIGN (ASSGMAIN.ASM):
#   - ASSIGN B=A  : maps B: → A: (installs TSR on first run, then updates
#                   mapping table via INT 2Fh on subsequent runs). Silent.
#   - DIR B:\...  : proves redirection works — ASSIGN patches drive letter
#                   in INT 21h path calls so B: is served by A:.
#   - ASSIGN      : clear all mappings (identity table). Silent.
#   Note: REPORT_STATUS ("Original X: set to Y:") is only printed when the
#   /STATUS flag is set; plain "ASSIGN B=A" produces no output.
#
# SUBST (SUBST.C):
#   - SUBST D: A:\SUBSTDIR : creates virtual drive D: → A:\SUBSTDIR. Silent.
#   - SUBST                 : lists all substitutions: "D: => A:\SUBSTDIR".
#   - SUBST D: /D           : removes the substitution. Silent.
#   Requires LASTDRIVE >= D — set via CONFIG.SYS LASTDRIVE=Z.
#
# JOIN (JOIN.C):
#   - JOIN B: A:\JOINDIR : joins physical drive B: (second floppy) to the
#                          directory A:\JOINDIR. B: is then inaccessible as a
#                          standalone drive; its contents appear at A:\JOINDIR.
#   - JOIN                : lists all joins: "B: => A:\JOINDIR".
#   - JOIN B: /D          : unjoin. B: becomes accessible again.
#   Requires a second physical floppy (B:) — created blank + formatted.
#   A test file is placed on B: so its presence at A:\JOINDIR can be verified.
#
# Run via: make test-assign-subst-join  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/asj-boot.img"
B_IMG="$OUT/asj-b.img"
SERIAL_LOG="$OUT/asj-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'rm -f "$B_IMG" 2>/dev/null; true' EXIT

echo "=== ASSIGN / SUBST / JOIN E2E tests (QEMU) ==="

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# ── Build test images ─────────────────────────────────────────────────────────
echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"

# CONFIG.SYS: LASTDRIVE=Z makes all drive letters A-Z available for SUBST/JOIN.
# Without this SUBST D: would fail if the default LASTDRIVE < D.
printf 'LASTDRIVE=Z\r\n' | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS

# Second floppy (B:) for JOIN test — blank, formatted, with a marker file.
dd if=/dev/zero bs=512 count=2880 of="$B_IMG" status=none
mformat -i "$B_IMG" -f 1440 ::
printf 'JOIN_B_FILE_CONTENT\r\n' | mcopy -o -i "$B_IMG" - ::BJOIN.TXT

{
    printf 'CTTY AUX\r\n'

    # ── ASSIGN B=A — redirect B: to A: ───────────────────────────────────────
    # ASSIGN is silent on success (no output, no "Original X: set to Y:" message
    # unless /STATUS is passed). Just installs TSR + sets mapping.
    printf 'ECHO ---ASSIGN---\r\n'
    printf 'ASSIGN B=A\r\n'
    printf 'ECHO ASSIGN_DONE\r\n'

    # ── ASSIGN verify — DIR B: redirected to A: ───────────────────────────────
    # With B: → A: active, DIR B:\COMMAND.COM shows A:\COMMAND.COM.
    printf 'ECHO ---ASSIGN-DIR---\r\n'
    printf 'DIR B:\COMMAND.COM\r\n'
    printf 'ECHO ASSIGN_DIR_DONE\r\n'

    # ── ASSIGN clear ──────────────────────────────────────────────────────────
    # ASSIGN with no args resets all mappings to identity. Silent.
    printf 'ECHO ---ASSIGN-CLEAR---\r\n'
    printf 'ASSIGN\r\n'
    printf 'ECHO ASSIGN_CLEAR_DONE\r\n'

    # ── SUBST D: A:\SUBSTDIR — create virtual drive D: ───────────────────────
    printf 'ECHO ---SUBST---\r\n'
    printf 'MD SUBSTDIR\r\n'
    printf 'SUBST D: A:\SUBSTDIR\r\n'
    printf 'ECHO SUBST_CREATE_DONE\r\n'

    # ── SUBST (list) — shows "D: => A:\SUBSTDIR" ─────────────────────────────
    printf 'ECHO ---SUBST-LIST---\r\n'
    printf 'SUBST\r\n'
    printf 'ECHO SUBST_LIST_DONE\r\n'

    # ── SUBST D: /D — remove substitution ────────────────────────────────────
    printf 'ECHO ---SUBST-DEL---\r\n'
    printf 'SUBST D: /D\r\n'
    printf 'ECHO SUBST_DEL_DONE\r\n'

    # ── JOIN B: A:\JOINDIR — join second floppy to a directory ───────────────
    # B: (second floppy) becomes inaccessible as a standalone drive; its
    # contents appear under A:\JOINDIR.
    printf 'ECHO ---JOIN---\r\n'
    printf 'MD JOINDIR\r\n'
    printf 'JOIN B: A:\JOINDIR\r\n'
    printf 'ECHO JOIN_CREATE_DONE\r\n'

    # ── JOIN (list) — shows "B: => A:\JOINDIR" ───────────────────────────────
    printf 'ECHO ---JOIN-LIST---\r\n'
    printf 'JOIN\r\n'
    printf 'ECHO JOIN_LIST_DONE\r\n'

    # ── JOIN verify — B:'s file is visible at A:\JOINDIR ────────────────────
    printf 'ECHO ---JOIN-DIR---\r\n'
    printf 'DIR A:\JOINDIR\r\n'
    printf 'ECHO JOIN_DIR_DONE\r\n'

    # ── JOIN B: /D — remove join ──────────────────────────────────────────────
    printf 'ECHO ---JOIN-DEL---\r\n'
    printf 'JOIN B: /D\r\n'
    printf 'ECHO JOIN_DEL_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Boot QEMU and capture serial output ──────────────────────────────────────
echo "Booting QEMU (may take ~90s)..."
rm -f "$SERIAL_LOG"
(while true; do sleep 0.5; printf '\r\n'; done) | \
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$B_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

# ── ASSIGN checks ─────────────────────────────────────────────────────────────
echo ""
echo "--- ASSIGN tests ---"

if grep -q "ASSIGN_DONE" "$SERIAL_LOG"; then
    ok "ASSIGN B=A (installed silently, batch continued)"
else
    fail "ASSIGN B=A (batch hung or crashed)"
fi

if grep -qi "COMMAND" "$SERIAL_LOG" && grep -q "ASSIGN_DIR_DONE" "$SERIAL_LOG"; then
    ok "ASSIGN B=A verify (DIR B:\\COMMAND.COM shows A: contents)"
else
    fail "ASSIGN B=A verify (expected 'COMMAND' in DIR B:\\COMMAND.COM output)"
fi

if grep -q "ASSIGN_CLEAR_DONE" "$SERIAL_LOG"; then
    ok "ASSIGN clear (no-arg call continued)"
else
    fail "ASSIGN clear (batch hung or crashed)"
fi

# ── SUBST checks ──────────────────────────────────────────────────────────────
echo ""
echo "--- SUBST tests ---"

if grep -q "SUBST_CREATE_DONE" "$SERIAL_LOG"; then
    ok "SUBST D: A:\\SUBSTDIR (created silently, batch continued)"
else
    fail "SUBST D: A:\\SUBSTDIR (batch hung or crashed)"
fi

if grep -q "D: => " "$SERIAL_LOG" && grep -q "SUBST_LIST_DONE" "$SERIAL_LOG"; then
    ok "SUBST list (shows 'D: => ...' for active substitution)"
else
    fail "SUBST list (expected 'D: => ' in SUBST output)"
fi

if grep -q "SUBST_DEL_DONE" "$SERIAL_LOG"; then
    ok "SUBST D: /D (removed silently, batch continued)"
else
    fail "SUBST D: /D (batch hung or crashed)"
fi

# ── JOIN checks ───────────────────────────────────────────────────────────────
echo ""
echo "--- JOIN tests ---"

if grep -q "JOIN_CREATE_DONE" "$SERIAL_LOG"; then
    ok "JOIN B: A:\\JOINDIR (joined silently, batch continued)"
else
    fail "JOIN B: A:\\JOINDIR (batch hung or crashed)"
fi

if grep -q "B: => " "$SERIAL_LOG" && grep -q "JOIN_LIST_DONE" "$SERIAL_LOG"; then
    ok "JOIN list (shows 'B: => ...' for active join)"
else
    fail "JOIN list (expected 'B: => ' in JOIN output)"
fi

if grep -qi "BJOIN" "$SERIAL_LOG" && grep -q "JOIN_DIR_DONE" "$SERIAL_LOG"; then
    ok "JOIN verify (B:'s BJOIN.TXT visible at A:\\JOINDIR)"
else
    fail "JOIN verify (expected BJOIN.TXT from B: to appear under A:\\JOINDIR)"
fi

if grep -q "JOIN_DEL_DONE" "$SERIAL_LOG"; then
    ok "JOIN B: /D (unjoined, batch continued)"
else
    fail "JOIN B: /D (batch hung or crashed)"
fi

# ── Completion check ──────────────────────────────────────────────────────────
echo ""
if grep -q "===DONE===" "$SERIAL_LOG"; then
    ok "Batch reached ===DONE==="
else
    fail "Batch did NOT reach ===DONE=== (hung or crashed early)"
    echo "--- last 30 lines of serial log ---"
    tail -30 "$SERIAL_LOG"
    echo "---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
