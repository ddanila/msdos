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

# ── Batch 1: full partition sequence (primary → extended → logical) ───────────
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
    # No stdin feed — FDISK with /Q has no interactive prompts. The continuous
    # \r\n feed was causing "Invalid parameter" + R6001 crashes by injecting
    # characters into the serial port while FDISK initializes.
    timeout 90 qemu-system-i386 \
        -display none \
        -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
        -drive if=ide,index=0,format=raw,file="$HDD_IMG",cache=writethrough \
        -boot a -m 4 \
        -serial stdio \
        < /dev/null \
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

def hexdump(data, n=64):
    return ' '.join('{:02x}'.format(b) for b in data[:n])

with open('$HDD_IMG', 'rb') as f:
    # ── MBR ──
    f.seek(446)
    e1 = f.read(16)  # primary
    e2 = f.read(16)  # extended

    pri_type  = e1[4]
    ext_type  = e2[4]
    ext_lba   = struct.unpack_from('<I', e2, 8)[0]
    ext_chs   = chs_to_lba(e2)

    # ── Find EBR: scan from ext_lba for up to 64 sectors ──
    log_type = 0
    used_method = 'none'
    ebr_hex = ''
    start = ext_lba if ext_lba > 0 else ext_chs
    if start > 0 and start * 512 < IMG_SIZE:
        # Dump the partition table area of the EBR sector for diagnostics
        f.seek(start * 512 + 446)
        ebr_raw = f.read(66)  # 4 entries (64 bytes) + 2 byte signature
        ebr_hex = hexdump(ebr_raw, 66)
        if len(ebr_raw) >= 16 and ebr_raw[4] in DOS_TYPES:
            log_type = ebr_raw[4]
            used_method = 'direct@{}'.format(start)
        else:
            # Scan ahead: some FDISKs put the EBR one track in
            for offset in range(1, 64):
                sec = start + offset
                if sec * 512 >= IMG_SIZE:
                    break
                f.seek(sec * 512 + 446)
                le1 = f.read(16)
                if len(le1) == 16 and le1[4] in DOS_TYPES:
                    log_type = le1[4]
                    used_method = 'scan@{}(+{})'.format(sec, offset)
                    break

    debug = 'lba={},chs={},method={},ebr_hex=[{}]'.format(ext_lba, ext_chs, used_method, ebr_hex)
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

# ══════════════════════════════════════════════════════════════════════════════
# Boot 2: Primary-only (no extended partition) — regression test for PTM P941
# ══════════════════════════════════════════════════════════════════════════════
#
# DISKOUT.C line 49: `if (find_partition_type(uc(EXTENDED)))` guards the block
# that writes logical drive info. A stray semicolon (fixed in d08cd94) turned
# this into a no-op, causing write_info() to access the extended partition table
# with an invalid index when no extended partition existed → crash/corruption.
#
# This test creates ONLY a primary partition, then creates another primary on a
# second FDISK call (which triggers write_info() to persist partition state).
# If the guard is broken, FDISK crashes during the second call.

BOOT_IMG2="$OUT/fdisk-boot2.img"
HDD_IMG2="$OUT/fdisk-hdd2.img"
SERIAL_LOG2="$OUT/fdisk-serial2.log"
trap 'rm -f "$HDD_IMG" "$HDD_IMG2" 2>/dev/null; true' EXIT

echo ""
echo "=== FDISK edge case: primary-only, no extended partition (PTM P941) ==="

echo "Building test image (boot 2)..."
cp "$FLOPPY" "$BOOT_IMG2"

# Batch: create primary partition, then invoke FDISK again (triggers write_info
# on a disk with no extended partition — the exact scenario PTM P941 describes).
{
    printf 'CTTY AUX\r\n'

    # Create a 5 MB primary partition on blank disk
    printf 'ECHO ---FDISK_PRIONLY---\r\n'
    printf 'FDISK 1 /PRI:5 /Q\r\n'
    printf 'ECHO FDISK_PRIONLY_DONE\r\n'

    # Second FDISK call — reads existing partition table (primary only, no
    # extended). write_info() must skip the logical drive block. If the
    # semicolon bug is present, this crashes with R6001 or corrupts memory.
    printf 'ECHO ---FDISK_NOEXT---\r\n'
    printf 'FDISK 1 /Q\r\n'
    printf 'IF ERRORLEVEL 2 ECHO FDISK_NOEXT_EL2\r\n'
    printf 'ECHO FDISK_NOEXT_DONE\r\n'

    printf 'ECHO ===DONE2===\r\n'
} | mcopy -o -i "$BOOT_IMG2" - ::AUTOEXEC.BAT

run_qemu2() {
    dd if=/dev/zero bs=1M count=20 of="$HDD_IMG2" status=none
    rm -f "$SERIAL_LOG2"
    timeout 90 qemu-system-i386 \
        -display none \
        -drive if=floppy,index=0,format=raw,file="$BOOT_IMG2",cache=writethrough \
        -drive if=ide,index=0,format=raw,file="$HDD_IMG2",cache=writethrough \
        -boot a -m 4 \
        -serial stdio \
        < /dev/null \
        2>/dev/null | tee "$SERIAL_LOG2" > /dev/null; true
}

echo "Booting QEMU (may take ~60s)..."
run_qemu2
if ! grep -q "FDISK_NOEXT_DONE" "$SERIAL_LOG2" 2>/dev/null; then
    echo "  FDISK did not complete (crash or hang); retrying..."
    run_qemu2
fi

echo ""
echo "--- FDISK primary-only checks ---"

# First call: create primary partition
if grep -q "FDISK_PRIONLY_DONE" "$SERIAL_LOG2"; then
    ok "FDISK 1 /PRI:5 /Q (primary-only disk, no extended)"
else
    fail "FDISK 1 /PRI:5 /Q (primary-only: batch hung or crashed)"
fi

# Second call: FDISK reads partition table with no extended partition.
# write_info() must skip the logical drive block (DISKOUT.C line 49 guard).
# Returns errorlevel 2 (/Q with no partition switches).
if grep -q "FDISK_NOEXT_EL2" "$SERIAL_LOG2"; then
    ok "FDISK 1 /Q on primary-only disk (errorlevel 2, no crash — PTM P941 guard works)"
else
    fail "FDISK 1 /Q on primary-only disk (expected errorlevel 2 — semicolon bug regression?)"
fi

if grep -q "FDISK_NOEXT_DONE" "$SERIAL_LOG2"; then
    ok "FDISK primary-only: batch continued after second call"
else
    fail "FDISK primary-only: batch hung or crashed (write_info crash without extended partition?)"
fi

# Verify MBR: entry 1 has a primary partition, entry 2 is empty (type 0x00)
read -r pri2_type ext2_type < <(python3 -c "
with open('$HDD_IMG2', 'rb') as f:
    f.seek(446)
    e1 = f.read(16)
    e2 = f.read(16)
    print('{:02x} {:02x}'.format(e1[4], e2[4]))
" 2>/dev/null)

case "$pri2_type" in
    01|04|06) ok "MBR entry 1: primary partition type 0x$pri2_type (primary-only disk)" ;;
    *)        fail "MBR entry 1: expected DOS type (01/04/06), got 0x${pri2_type:-?}" ;;
esac

if [[ "$ext2_type" == "00" ]]; then
    ok "MBR entry 2: type 0x00 (no extended partition — confirms primary-only scenario)"
else
    fail "MBR entry 2: expected type 0x00 (empty), got 0x${ext2_type:-?}"
fi

if grep -q "===DONE2===" "$SERIAL_LOG2"; then
    ok "Batch 2 reached ===DONE2==="
else
    fail "Batch 2 did NOT reach ===DONE2=== (hung or crashed early)"
    echo "--- last 20 lines of serial log 2 ---"
    tail -20 "$SERIAL_LOG2"
    echo "---"
fi

# Dump serial log on any failure
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "--- full serial log 2 (for debugging) ---"
    cat "$SERIAL_LOG2" 2>/dev/null || echo "(empty)"
    echo "--- end serial log 2 ---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
