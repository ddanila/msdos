#!/bin/bash
# tests/test_sys.sh — E2E test for SYS.COM: transfer system files to blank floppy and verify boot.
#
# Flow:
#   1. Build floppy-sys-boot.img  = floppy.img + AUTOEXEC.BAT running SYS B:
#   2. Build floppy-sys-target.img = blank FAT12 floppy (destination)
#   3. Boot QEMU with A: = boot img, B: = target img; capture COM1
#   4. Verify "System transferred" appears in COM1 output
#   5. Add AUTOEXEC.BAT (CTTY AUX + VER) to target img via mcopy on host
#   6. Boot QEMU from target img alone; capture COM1
#   7. Verify "MS-DOS" appears in COM1 output
#
# Run via: make test-sys  (requires 'make deploy' first)

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

# ── Step 1: build boot floppy (our img + AUTOEXEC.BAT that runs SYS B:) ────
echo "Building test images..."
cp "$FLOPPY" "$SYS_BOOT"
printf 'CTTY AUX\r\nSYS B:\r\n' | mcopy -i "$SYS_BOOT" - ::AUTOEXEC.BAT

# ── Step 2: create blank FAT12 target floppy ────────────────────────────────
dd if=/dev/zero bs=512 count=2880 of="$SYS_TARGET" status=none
mformat -i "$SYS_TARGET" -f 1440 ::

# ── Step 3: boot A: (our floppy), let SYS B: run ────────────────────────────
echo "Running SYS B: in QEMU..."
rm -f "$SYS_LOG"
timeout 15 qemu-system-i386 \
    -drive if=floppy,index=0,format=raw,file="$SYS_BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$SYS_TARGET",cache=writethrough \
    -boot a -m 4 \
    -display none \
    -serial file:"$SYS_LOG" \
    2>/dev/null; true

# ── Step 4: verify SYS reported success ─────────────────────────────────────
if grep -qi "System transferred" "$SYS_LOG"; then
    ok "SYS B: reported 'System transferred'"
else
    fail "SYS B: did not report success"
    echo "--- serial log ---"; cat "$SYS_LOG"; echo "---"
fi

# ── Step 5: add COMMAND.COM + AUTOEXEC.BAT to target for boot verification ──
# SYS only transfers IO.SYS and MSDOS.SYS; COMMAND.COM must be copied separately.
mcopy -i "$SYS_TARGET" "$COMMAND_COM" ::COMMAND.COM
printf 'CTTY AUX\r\nVER\r\n' | mcopy -o -i "$SYS_TARGET" - ::AUTOEXEC.BAT

# ── Step 6: boot from the SYS'd floppy ──────────────────────────────────────
echo "Booting SYS'd floppy..."
rm -f "$SYS_BOOT2_LOG"
timeout 15 qemu-system-i386 \
    -drive if=floppy,index=0,format=raw,file="$SYS_TARGET",cache=writethrough \
    -boot a -m 4 \
    -display none \
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
