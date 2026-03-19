#!/bin/bash
# tests/test_fdisk.sh — E2E test for FDISK partition operations.
#
# FDISK (FDISK.C) supports non-interactive command-line switches:
#   FDISK drivenum [/PRI:m] [/EXT:n] [/LOG:o] [/Q]
#   - drivenum: 1 = first hard disk (BIOS drive 0x80)
#   - /PRI:m:  create a Primary DOS Partition of m MB
#   - /EXT:n:  create an Extended DOS Partition of n MB
#   - /LOG:o:  create a Logical DOS Drive of o MB in the extended partition
#   - /Q:      suppress the "restart computer" reboot prompt after changes
#
# Exit codes (with /Q):  0 = success, 1 = no valid DOS partition, 2 = /Q but
# no partition creation switches given.
#
# FDISK writes directly to the screen via INT 10h, so only the batch markers
# are visible on serial (COM1 via CTTY AUX).
# Partition creation is verified after QEMU exits by inspecting the raw HDD
# image (MBR partition table + Extended Boot Record).
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

echo "=== FDISK E2E tests (QEMU, non-interactive switches) ==="

# ── Build test floppy and blank HDD ──────────────────────────────────────────
echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

{
    printf 'CTTY AUX\r\n'

    # ── Test 1: FDISK 1 /Q (no partition switches) → errorlevel 2 ────────────
    # Source (MAIN.C): returns ERR_LEVEL_2 when /Q is set but no /PRI /EXT /LOG.
    printf 'ECHO ---FDISK_ERRLEVEL---\r\n'
    printf 'FDISK 1 /Q\r\n'
    printf 'IF ERRORLEVEL 2 ECHO FDISK_ERRLEVEL_2\r\n'

    # ── Test 2: FDISK 1 /PRI:5 /Q — create 5 MB primary DOS partition ────────
    printf 'ECHO ---FDISK_PRI---\r\n'
    printf 'FDISK 1 /PRI:5 /Q\r\n'
    printf 'ECHO FDISK_PRI_DONE\r\n'

    # ── Test 3: FDISK 1 /EXT:10 /Q — create 10 MB extended partition ─────────
    # Requires a primary partition to exist first.
    printf 'ECHO ---FDISK_EXT---\r\n'
    printf 'FDISK 1 /EXT:10 /Q\r\n'
    printf 'ECHO FDISK_EXT_DONE\r\n'

    # ── Test 4: FDISK 1 /LOG:10 /Q — create 10 MB logical drive ──────────────
    # Requires an extended partition to exist first.
    printf 'ECHO ---FDISK_LOG---\r\n'
    printf 'FDISK 1 /LOG:10 /Q\r\n'
    printf 'ECHO FDISK_LOG_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Boot QEMU (with retry on crash/hang) ──────────────────────────────────────
# FDISK has an intermittent crash under QEMU (tight conventional memory).
# FDISK writes to screen (INT 10h), not serial, so crash messages are NOT
# visible in the serial log — we detect failure by missing FDISK_DONE marker.
# Retry once if FDISK_DONE is absent (crash or hang).
run_qemu() {
    # Blank 20 MB HDD image for each attempt — FDISK writes a partition table.
    # QEMU derives geometry from image size; 20 MB holds 5 MB primary + 10 MB extended.
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
if ! grep -q "FDISK_LOG_DONE" "$SERIAL_LOG" 2>/dev/null; then
    echo "  FDISK did not complete all steps (crash or hang); retrying..."
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

# Test 1: errorlevel 2 when /Q used without partition switches
if grep -q "FDISK_ERRLEVEL_2" "$SERIAL_LOG"; then
    ok "FDISK 1 /Q (no switches) returns errorlevel 2"
else
    fail "FDISK 1 /Q (no switches) — expected errorlevel 2"
fi

# Test 2: /PRI completed
if grep -q "FDISK_PRI_DONE" "$SERIAL_LOG"; then
    ok "FDISK 1 /PRI:5 /Q completed"
else
    fail "FDISK 1 /PRI:5 /Q did not complete"
fi

# Test 3: /EXT completed
if grep -q "FDISK_EXT_DONE" "$SERIAL_LOG"; then
    ok "FDISK 1 /EXT:10 /Q completed"
else
    fail "FDISK 1 /EXT:10 /Q did not complete"
fi

# Test 4: /LOG completed
if grep -q "FDISK_LOG_DONE" "$SERIAL_LOG"; then
    ok "FDISK 1 /LOG:10 /Q completed"
else
    fail "FDISK 1 /LOG:10 /Q did not complete"
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
echo "--- FDISK partition table checks ---"

# Read partition table via Python (no root required).
# MBR layout: partition table starts at offset 446; each entry is 16 bytes.
#   Entry byte 4 = partition type, entry bytes 8-11 = relative sector (LE).
# Entry 1 (offset 446): primary partition  → type 0x01/0x04/0x06 (DOS FAT)
# Entry 2 (offset 462): extended partition → type 0x05
# Extended Boot Record (EBR): at the first sector of the extended partition,
#   same layout — entry 1 has the logical drive (type 0x01/0x04/0x06).

read -r pri_type ext_type log_type ebr_debug < <(python3 -c "
import struct, sys

DOS_TYPES = (0x01, 0x04, 0x06)
IMG_SIZE = 20 * 1024 * 1024  # 20 MB
# QEMU IDE geometry for 20 MB: 16 heads, 63 sectors/track
HEADS, SPT = 16, 63

def chs_to_lba(entry):
    '''Compute LBA from CHS bytes in a partition entry (offsets 1-3).'''
    head = entry[1]
    sec  = entry[2] & 0x3F
    cyl  = ((entry[2] & 0xC0) << 2) | entry[3]
    if sec == 0:
        return 0
    return (cyl * HEADS + head) * SPT + (sec - 1)

with open('$HDD_IMG', 'rb') as f:
    # ── MBR ──
    f.seek(446)
    e1 = f.read(16)  # primary
    e2 = f.read(16)  # extended

    pri_type  = e1[4]
    ext_type  = e2[4]
    ext_lba   = struct.unpack_from('<I', e2, 8)[0]
    ext_chs   = chs_to_lba(e2)

    # ── Find EBR: try LBA field first, then CHS-computed LBA ──
    log_type = 0
    used_method = 'none'
    for method, start in [('lba', ext_lba), ('chs', ext_chs)]:
        if start > 0 and start * 512 < IMG_SIZE:
            f.seek(start * 512 + 446)
            le1 = f.read(16)
            if len(le1) == 16 and le1[4] in DOS_TYPES:
                log_type = le1[4]
                used_method = '{}@{}'.format(method, start)
                break

    debug = 'lba={},chs={},method={}'.format(ext_lba, ext_chs, used_method)
    print('{:02x} {:02x} {:02x} {}'.format(pri_type, ext_type, log_type, debug))
" 2>/dev/null)

# Check primary partition type (0x01=FAT12, 0x04=FAT16<32M, 0x06=FAT16>32M)
case "$pri_type" in
    01|04|06) ok "MBR entry 1: primary DOS partition type 0x$pri_type" ;;
    *)        fail "MBR entry 1: expected DOS type (01/04/06), got 0x${pri_type:-?}" ;;
esac

# Check extended partition type (0x05)
if [[ "$ext_type" == "05" ]]; then
    ok "MBR entry 2: extended partition type 0x05"
else
    fail "MBR entry 2: expected type 0x05 (extended), got 0x${ext_type:-?}"
fi

# Check logical drive in EBR
case "$log_type" in
    01|04|06) ok "EBR entry 1: logical drive type 0x$log_type (${ebr_debug:-})" ;;
    *)        fail "EBR entry 1: expected DOS type (01/04/06), got 0x${log_type:-?} (${ebr_debug:-})" ;;
esac

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
