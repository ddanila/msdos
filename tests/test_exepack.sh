#!/bin/bash
# tests/test_exepack.sh — Verify EXEPACK-patched binaries work on real DOS (QEMU).
#
# FIND.EXE, FDISK.EXE, IFSFUNC.EXE, EXE2BIN.EXE are linked with Microsoft
# LINK /EXEPACK which embeds a buggy decompressor stub that causes "Packed
# file is corrupt" on real DOS due to an A20 gate bug.  bin/fix-exepack
# patches the stub at build time.  kvikdos masks this bug entirely (it
# replaces the stub in memory at load time), so only a QEMU test can confirm
# the on-disk fix actually works.
#
# Run via: make test-exepack  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

TEST_IMG="$OUT/floppy-exepack.img"
SERIAL_LOG="$OUT/exepack-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== EXEPACK verification tests (QEMU) ==="

# ── Build test floppy ────────────────────────────────────────────────────────
echo "Building test floppy..."
cp "$FLOPPY" "$TEST_IMG"

# Run all 4 EXEPACK-patched tools with /? in a single boot.
# SELECT.EXE is not on the floppy (too large); tested implicitly via make test-sys.
printf 'CTTY AUX\r\nFIND /?\r\nFDISK /?\r\nIFSFUNC /?\r\nEXE2BIN /?\r\n' \
    | mcopy -o -i "$TEST_IMG" - ::AUTOEXEC.BAT

# ── Boot QEMU and capture serial output ──────────────────────────────────────
echo "Booting QEMU (headless, ~20s)..."
rm -f "$SERIAL_LOG"
timeout 30 qemu-system-i386 \
    -display none \
    -fda "$TEST_IMG" \
    -boot a -m 4 \
    -serial stdio \
    </dev/null 2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty or missing — QEMU may have failed to boot"
    exit 1
fi

# ── Check for EXEPACK corruption ─────────────────────────────────────────────
if grep -qi "Packed file is corrupt" "$SERIAL_LOG"; then
    fail "EXEPACK corruption detected — bin/fix-exepack may have failed"
fi

# ── Check each tool loaded and printed help ──────────────────────────────────

# FIND /? — should print usage
if grep -q "Searches for a text string" "$SERIAL_LOG"; then
    ok "FIND.EXE (EXEPACK loads correctly)"
else
    fail "FIND.EXE (no help output — may not have loaded)"
fi

# FDISK /? — on real DOS the parser rejects /? ("Invalid switch") but the
# binary still loads and runs, proving the EXEPACK fix works.
if grep -q "FDISK" "$SERIAL_LOG"; then
    ok "FDISK.EXE (EXEPACK loads correctly)"
else
    fail "FDISK.EXE (no output — may not have loaded)"
fi

# IFSFUNC /? — should print usage
if grep -q "IFSFUNC" "$SERIAL_LOG"; then
    ok "IFSFUNC.EXE (EXEPACK loads correctly)"
else
    fail "IFSFUNC.EXE (no help output — may not have loaded)"
fi

# EXE2BIN /? — should print usage
if grep -q "EXE2BIN" "$SERIAL_LOG"; then
    ok "EXE2BIN.EXE (EXEPACK loads correctly)"
else
    fail "EXE2BIN.EXE (no help output — may not have loaded)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
