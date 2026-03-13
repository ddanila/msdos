#!/bin/bash
# tests/test_sys.sh — E2E test for SYS.COM: transfer system files to blank floppy and verify boot.
#
# Flow:
#   1. Build floppy-sys-boot.img = floppy.img + AUTOEXEC.BAT
#      (AUTOEXEC: CTTY AUX → FORMAT B: → SYS B:)
#      FORMAT.COM and SYS.COM are already on floppy.img.
#   2. Build floppy-sys-target.img = completely blank image (all zeros, no FAT)
#   3. Boot QEMU with A: = boot img, B: = blank target
#      -serial stdio: COM1 ↔ QEMU stdin/stdout
#      A subshell feeds FORMAT responses at timed intervals via stdin.
#      QEMU stdout (COM1 output) is captured to log via tee.
#      FORMAT.COM formats B: from scratch, then SYS.COM transfers system files.
#   4. Check log for "Format complete" and "System transferred"
#   5. Add COMMAND.COM + AUTOEXEC.BAT (CTTY AUX + VER) to target via mcopy
#   6. Boot QEMU from target; verify "MS-DOS" on COM1
#
# Run via: make test-sys  (requires 'make deploy' first)
#
# FORMAT B: prompts (all via COM1 because CTTY AUX redirects console):
#   "press ENTER when ready"          → \r\n  (sent after ~5s boot)
#   "Volume label ... ENTER for none" → \r\n  (sent after formatting, ~10s)
#   "Format another (Y/N)?"           → N\r\n (sent after stats, ~2s)
# Then SYS B: runs (~5s) and prints "System transferred".
# Total QEMU run: ~22s; timeout set to 40s for safety.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/MS-DOS/v4.0/src"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
COMMAND_COM="$SRC/CMD/COMMAND/COMMAND.COM"

SYS_BOOT="$OUT/floppy-sys-boot.img"
SYS_TARGET="$OUT/floppy-sys-target.img"
SYS_LOG="$OUT/sys-serial.log"
SYS_BOOT2_LOG="$OUT/sys-boot2-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== SYS.COM e2e test ==="

# ── Step 1: build boot floppy ───────────────────────────────────────────────
# floppy.img already has FORMAT.COM and SYS.COM; just add the AUTOEXEC.BAT.
echo "Building test images..."
cp "$FLOPPY" "$SYS_BOOT"
printf 'CTTY AUX\r\nFORMAT B:\r\nSYS B:\r\n' | mcopy -i "$SYS_BOOT" - ::AUTOEXEC.BAT

# ── Step 2: create completely blank target floppy ───────────────────────────
# All zeros — no FAT, no boot sector. FORMAT.COM will set it up from scratch.
dd if=/dev/zero bs=512 count=2880 of="$SYS_TARGET" status=none

# ── Step 3: boot A:, FORMAT B:, SYS B: ─────────────────────────────────────
# -serial stdio maps COM1 to QEMU's stdin/stdout.
# The subshell on the left feeds FORMAT responses at timed intervals.
# tee on the right captures COM1 output to log.
echo "Running FORMAT B: + SYS B: in QEMU (may take ~30s)..."
rm -f "$SYS_LOG"
(
    sleep 5;  printf '\r\n'   # ENTER: "Insert diskette ... press ENTER when ready"
    sleep 10; printf '\r\n'   # ENTER: "Volume label (11 characters, ENTER for none)?"
    sleep 2;  printf 'N\r\n'  # N:     "Format another (Y/N)?"
    sleep 15                  # keep stdin open while SYS B: runs + QEMU winds down
) | timeout 40 qemu-system-i386 \
    -drive if=floppy,index=0,format=raw,file="$SYS_BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$SYS_TARGET",cache=writethrough \
    -boot a -m 4 -display none \
    -serial stdio \
    2>/dev/null | tee "$SYS_LOG" > /dev/null; true

# ── Step 4: verify FORMAT + SYS reported success ────────────────────────────
if grep -qi "Format complete" "$SYS_LOG"; then
    ok "FORMAT B: completed"
else
    fail "FORMAT B: did not complete"
    echo "--- serial log ---"; cat "$SYS_LOG"; echo "---"
fi

if grep -qi "System transferred" "$SYS_LOG"; then
    ok "SYS B: reported 'System transferred'"
else
    fail "SYS B: did not report success"
    echo "--- serial log ---"; cat "$SYS_LOG"; echo "---"
fi

# ── Step 5: add COMMAND.COM + AUTOEXEC.BAT to target ────────────────────────
# SYS only transfers IO.SYS and MSDOS.SYS; COMMAND.COM must be added separately.
mcopy -i "$SYS_TARGET" "$COMMAND_COM" ::COMMAND.COM
printf 'CTTY AUX\r\nVER\r\n' | mcopy -o -i "$SYS_TARGET" - ::AUTOEXEC.BAT

# ── Step 6: boot from the SYS'd floppy ──────────────────────────────────────
echo "Booting SYS'd floppy..."
rm -f "$SYS_BOOT2_LOG"
timeout 15 qemu-system-i386 \
    -drive if=floppy,index=0,format=raw,file="$SYS_TARGET",cache=writethrough \
    -boot a -m 4 -display none \
    -serial file:"$SYS_BOOT2_LOG" \
    2>/dev/null; true

# ── Step 7: verify boot ──────────────────────────────────────────────────────
if grep -q "MS-DOS" "$SYS_BOOT2_LOG"; then
    ok "SYS'd floppy boots MS-DOS successfully"
else
    fail "SYS'd floppy did not boot MS-DOS"
    echo "--- serial log ---"; cat "$SYS_BOOT2_LOG"; echo "---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
