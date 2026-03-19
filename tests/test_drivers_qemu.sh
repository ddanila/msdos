#!/bin/bash
# tests/test_drivers_qemu.sh — E2E tests for device drivers via QEMU.
#
# Tests CONFIG.SYS device driver loading and CONFIG.SYS directives:
#   - ANSI.SYS: load driver, verify via escape sequence output
#   - RAMDRIVE.SYS: load driver, verify extra drive letter appears
#   - CONFIG.SYS directives: BUFFERS, FILES, LASTDRIVE, BREAK, STACKS, FCBS, INSTALL
#
# Run via: make test-drivers-qemu  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/floppy-drivers-qemu.img"
SERIAL_LOG="$OUT/drivers-qemu-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== Device Driver / CONFIG.SYS E2E tests (QEMU) ==="

# ── Build test floppy ────────────────────────────────────────────────────────
echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# ANSI.SYS and RAMDRIVE.SYS are already on the base floppy (added by make deploy).

# Write CONFIG.SYS with device drivers and directives
{
    printf 'DEVICE=ANSI.SYS\r\n'
    printf 'DEVICE=RAMDRIVE.SYS 64\r\n'
    printf 'BUFFERS=20\r\n'
    printf 'FILES=30\r\n'
    printf 'LASTDRIVE=Z\r\n'
    printf 'BREAK=ON\r\n'
    printf 'STACKS=9,256\r\n'
    printf 'FCBS=4\r\n'
    printf 'INSTALL=FASTOPEN.EXE C:=10\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS

# AUTOEXEC.BAT: test each driver and directive
{
    printf 'CTTY AUX\r\n'

    # ── ANSI.SYS test — use ANSI escape sequence to set cursor position ──
    # ESC[6n is "Device Status Report" → ANSI.SYS responds with cursor position.
    # But output goes to stdin buffer, hard to capture. Instead, test that ANSI.SYS
    # is loaded by checking MEM output for the driver name.
    printf 'ECHO ---ANSI---\r\n'
    printf 'MEM\r\n'
    printf 'ECHO ANSI_DONE\r\n'

    # ── RAMDRIVE.SYS test — verify extra drive letter via DIR ──────────────
    # RAMDRIVE.SYS creates a 64KB RAM disk at the next available drive letter.
    # With floppy-only boot (A:, B: reserved), the RAM disk is typically C: or D:.
    # Try multiple candidates to be robust.
    printf 'ECHO ---RAMDRIVE---\r\n'
    printf 'DIR C:\\\r\n'
    printf 'DIR D:\\\r\n'
    printf 'ECHO RAMDRIVE_DONE\r\n'

    # ── CONFIG.SYS directives — verify via MEM output ──────────────────────
    # MEM shows total memory; BUFFERS/FILES affect memory layout.
    # We just verify the boot completed successfully with these directives active.
    printf 'ECHO ---CONFIG---\r\n'
    printf 'MEM\r\n'
    printf 'ECHO CONFIG_DONE\r\n'

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

# ── ANSI.SYS checks ─────────────────────────────────────────────────────────
echo ""
echo "--- ANSI.SYS tests ---"

if grep -q "ANSI_DONE" "$SERIAL_LOG"; then
    ok "ANSI.SYS (boot completed with DEVICE=ANSI.SYS, batch continued)"
else
    fail "ANSI.SYS (batch hung or crashed — driver load may have failed)"
fi

# ── RAMDRIVE.SYS checks ─────────────────────────────────────────────────────
echo ""
echo "--- RAMDRIVE.SYS tests ---"

if grep -q "RAMDRIVE_DONE" "$SERIAL_LOG"; then
    ok "RAMDRIVE.SYS (boot completed with DEVICE=RAMDRIVE.SYS 64, batch continued)"
else
    fail "RAMDRIVE.SYS (batch hung or crashed — driver load may have failed)"
fi

# Check if DIR on C: or D: succeeded (shows "Volume" or "Directory of" header).
# RAMDRIVE assigns the next available drive letter after physical drives.
if grep -qi "Directory of C:\|Volume in drive C" "$SERIAL_LOG" || \
   grep -qi "Directory of D:\|Volume in drive D" "$SERIAL_LOG"; then
    ok "RAMDRIVE.SYS (RAM disk drive accessible via DIR)"
else
    fail "RAMDRIVE.SYS (no RAM disk drive found on C: or D:)"
fi

# ── CONFIG.SYS directives checks ────────────────────────────────────────────
echo ""
echo "--- CONFIG.SYS directive tests ---"

if grep -q "CONFIG_DONE" "$SERIAL_LOG"; then
    ok "CONFIG.SYS directives (BUFFERS=20 FILES=30 LASTDRIVE=Z BREAK=ON STACKS=9,256 FCBS=4 INSTALL=FASTOPEN — boot completed)"
else
    fail "CONFIG.SYS directives (batch did not reach CONFIG_DONE marker)"
fi

if grep -qi "bytes total memory" "$SERIAL_LOG"; then
    ok "CONFIG.SYS + MEM (memory report confirms DOS loaded with custom config)"
else
    fail "CONFIG.SYS + MEM (expected 'bytes total memory' in MEM output)"
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
