#!/bin/bash
# tests/test_fdisk.sh — E2E test for FDISK creating a primary DOS partition.
#
# FDISK (FDISK.C) supports non-interactive command-line switches:
#   FDISK 1 /PRI:5 /Q
#   - 1:      operate on first hard disk (BIOS drive 0x80)
#   - /PRI:5: create a 5 MB Primary DOS Partition
#   - /Q:     suppress the "restart computer" reboot prompt after changes
#
# FDISK writes directly to the screen via INT 10h, so only the batch markers
# (FDISK_DONE, ===DONE===) are visible on serial (COM1 via CTTY AUX).
# Partition creation is verified after QEMU exits by running 'fdisk -l' on
# the host against the raw HDD image.
#
# QEMU setup:
#   - Boot floppy (A:) carries FDISK.EXE and the batch script.
#   - Blank 20 MB IDE hard disk image is attached as the first fixed disk.
#   - BIOS presents the IDE disk as drive 0x80 → FDISK drive number 1.
#
# Run via: make test-fdisk  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/fdisk-boot.img"
HDD_IMG="$OUT/fdisk-hdd.img"
SERIAL_LOG="$OUT/fdisk-serial.log"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'rm -f "$HDD_IMG" 2>/dev/null; true' EXIT

echo "=== FDISK E2E tests (QEMU, non-interactive /PRI switch) ==="

# ── Build test floppy and blank HDD ──────────────────────────────────────────
echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

{
    printf 'CTTY AUX\r\n'

    # ── FDISK 1 /PRI:5 /Q — create 5 MB primary DOS partition, no reboot ─────
    # /Q suppresses the "restart computer" prompt so the batch continues.
    # FDISK writes status to the screen (INT 10h), not to COM1, so only the
    # FDISK_DONE echo is captured over serial.
    printf 'ECHO ---FDISK---\r\n'
    printf 'FDISK 1 /PRI:5 /Q\r\n'
    printf 'ECHO FDISK_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Boot QEMU (with retry on crash/hang) ──────────────────────────────────────
# FDISK has an intermittent crash under QEMU (tight conventional memory).
# FDISK writes to screen (INT 10h), not serial, so crash messages are NOT
# visible in the serial log — we detect failure by missing FDISK_DONE marker.
# Retry once if FDISK_DONE is absent (crash or hang).
run_qemu() {
    # Blank 20 MB HDD image for each attempt — FDISK writes a partition table.
    # QEMU derives geometry from image size; 20 MB holds a 5 MB primary partition.
    dd if=/dev/zero bs=1M count=20 of="$HDD_IMG" status=none
    rm -f "$SERIAL_LOG"
    (while true; do sleep 0.5; printf '\r\n'; done) | \
    timeout 90 qemu-system-i386 \
        -display none \
        -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
        -drive if=ide,index=0,format=raw,file="$HDD_IMG",cache=writethrough \
        -boot a -m 4 \
        -serial stdio \
        2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true
}

echo "Booting QEMU (may take ~60s)..."
run_qemu
if ! grep -q "FDISK_DONE" "$SERIAL_LOG" 2>/dev/null; then
    echo "  FDISK did not complete (crash or hang); retrying..."
    echo "  --- attempt 1 serial log ---"
    cat "$SERIAL_LOG" 2>/dev/null || echo "  (empty)"
    echo "  ---"
    run_qemu
fi

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

# ── Serial log checks ─────────────────────────────────────────────────────────
echo ""
echo "--- FDISK serial log checks ---"

if grep -q "FDISK_DONE" "$SERIAL_LOG"; then
    ok "FDISK 1 /PRI:5 /Q (returned to batch without hang)"
else
    fail "FDISK 1 /PRI:5 /Q (batch hung or crashed after FDISK)"
fi

if grep -q "===DONE===" "$SERIAL_LOG"; then
    ok "Batch reached ===DONE==="
else
    fail "Batch did NOT reach ===DONE=== (hung or crashed early)"
fi

# Always dump serial log on any failure for CI debugging
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "--- full serial log (for debugging) ---"
    cat "$SERIAL_LOG" 2>/dev/null || echo "(empty)"
    echo "--- end serial log ---"
fi

# ── Post-QEMU partition table check ───────────────────────────────────────────
echo ""
echo "--- FDISK partition table check ---"

# Read the MBR partition type byte directly via Python (no root required).
# MBR layout: partition table starts at offset 446; each entry is 16 bytes.
# Byte 4 of the first entry (offset 446+4 = 450) is the partition type.
# FDISK creates type 0x04 (FAT16 <32 MB) for a 5 MB primary partition.
type_hex=$(python3 -c "
with open('$HDD_IMG', 'rb') as f:
    f.seek(450)
    b = f.read(1)
    print('{:02x}'.format(b[0]) if b else '00')
" 2>/dev/null)

if [[ -n "$type_hex" && "$type_hex" != "00" ]]; then
    ok "FDISK partition table: DOS partition type 0x$type_hex written to MBR"
else
    fail "FDISK partition table: no partition type in MBR (got '0x${type_hex:-?}')"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
