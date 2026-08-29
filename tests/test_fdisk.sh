#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

BOOT_IMG="$OUT/fdisk-boot.img"
HDD_IMG="$OUT/fdisk-hdd.img"
SERIAL_LOG="$OUT/fdisk-serial.log"
EXIT_COM="$OUT/qemu-exit.com"

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

echo "Building test image..."
cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'

    printf 'ECHO ---FDISK_ERRLEVEL---\r\n'
    printf 'FDISK 1 /Q\r\n'
    printf 'IF ERRORLEVEL 2 ECHO FDISK_ERRLEVEL_2\r\n'

    printf 'ECHO ---FDISK_PRI---\r\n'
    printf 'FDISK 1 /PRI:5 /Q\r\n'
    printf 'ECHO FDISK_PRI_DONE\r\n'

    printf 'ECHO ---FDISK_EXT---\r\n'
    printf 'FDISK 1 /EXT:10 /Q\r\n'
    printf 'ECHO FDISK_EXT_DONE\r\n'

    printf 'ECHO ---FDISK_LOG---\r\n'
    printf 'FDISK 1 /LOG:10 /Q\r\n'
    printf 'ECHO FDISK_LOG_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

run_qemu() {
    dd if=/dev/zero bs=1M count=20 of="$HDD_IMG" status=none
    rm -f "$SERIAL_LOG"
    # FDISK /Q needs no input, and incoming serial IRQs race its initialization.
    timeout 90 qemu-system-i386 \
        -display none \
        -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
        -drive if=ide,index=0,format=raw,file="$HDD_IMG",cache=writethrough \
        -boot a -m 4 \
        -serial stdio \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        < /dev/null \
        2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true
}

hdd_has_ext() {
    python3 -c "
import sys
with open('$HDD_IMG', 'rb') as f:
    f.seek(466)
    sys.exit(0 if f.read(1) == b'\\x05' else 1)
" 2>/dev/null
}

echo "Booting QEMU (may take ~60s)..."
for attempt in 1 2 3; do
    run_qemu
    if grep -q "FDISK_LOG_DONE" "$SERIAL_LOG" 2>/dev/null && hdd_has_ext; then
        break
    fi
    echo "  FDISK did not complete all steps (attempt $attempt/3); retrying..."
    echo "  --- attempt $attempt serial log ---"
    cat "$SERIAL_LOG" 2>/dev/null || echo "  (empty)"
    echo "  ---"
done

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

echo ""
echo "--- FDISK serial log checks ---"

if grep -q "FDISK_PRI" "$SERIAL_LOG"; then
    ok "FDISK 1 /Q (no switches, batch continued)"
else
    fail "FDISK 1 /Q (batch hung or crashed)"
fi

if grep -q "FDISK_PRI_DONE" "$SERIAL_LOG"; then
    ok "FDISK 1 /PRI:5 /Q completed"
else
    fail "FDISK 1 /PRI:5 /Q did not complete"
fi

if grep -q "FDISK_EXT_DONE" "$SERIAL_LOG"; then
    ok "FDISK 1 /EXT:10 /Q completed"
else
    fail "FDISK 1 /EXT:10 /Q did not complete"
fi

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

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "--- full serial log (for debugging) ---"
    cat "$SERIAL_LOG" 2>/dev/null || echo "(empty)"
    echo "--- end serial log ---"
fi

echo ""
echo "--- FDISK partition table checks ---"


read -r pri_type ext_type log_type geometry_ok ebr_debug < <(python3 -c "
import struct, sys

DOS_TYPES = (0x01, 0x04, 0x06)
IMG_SIZE = 20 * 1024 * 1024
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
    f.seek(446)
    e1 = f.read(16)
    e2 = f.read(16)

    pri_type  = e1[4]
    ext_type  = e2[4]
    pri_lba, pri_size = struct.unpack_from('<II', e1, 8)
    ext_lba   = struct.unpack_from('<I', e2, 8)[0]
    ext_size  = struct.unpack_from('<I', e2, 12)[0]
    ext_chs   = chs_to_lba(e2)

    log_type = 0
    used_method = 'none'
    ebr_hex = ''
    log_rel = log_size = ebr_sector = 0
    start = ext_lba if ext_lba > 0 else ext_chs
    if start > 0 and start * 512 < IMG_SIZE:
        f.seek(start * 512 + 446)
        ebr_raw = f.read(66)
        ebr_hex = hexdump(ebr_raw, 66)
        if len(ebr_raw) >= 16 and ebr_raw[4] in DOS_TYPES:
            log_type = ebr_raw[4]
            log_rel, log_size = struct.unpack_from('<II', ebr_raw, 8)
            ebr_sector = start
            used_method = 'direct@{}'.format(start)
        else:
            for offset in range(1, 64):
                sec = start + offset
                if sec * 512 >= IMG_SIZE:
                    break
                f.seek(sec * 512 + 446)
                le1 = f.read(16)
                if len(le1) == 16 and le1[4] in DOS_TYPES:
                    log_type = le1[4]
                    log_rel, log_size = struct.unpack_from('<II', le1, 8)
                    ebr_sector = sec
                    used_method = 'scan@{}(+{})'.format(sec, offset)
                    break

    primary_bytes = pri_size * 512
    logical_bytes = log_size * 512
    logical_lba = ebr_sector + log_rel
    geometry_ok = (
        pri_lba > 0 and 5 * 1024 * 1024 <= primary_bytes <= 6 * 1024 * 1024
        and pri_lba + pri_size <= ext_lba
        and ext_lba == ext_chs and ext_size > 0
        and ext_lba <= ebr_sector < ext_lba + ext_size
        and 10 * 1024 * 1024 <= logical_bytes <= 11 * 1024 * 1024
        and logical_lba >= ext_lba
        and logical_lba + log_size <= ext_lba + ext_size
        and ebr_hex.endswith('55 aa')
    )
    debug = 'pri={}:{} ext={}:{} log={}:{} method={}'.format(
        pri_lba, pri_size, ext_lba, ext_size, logical_lba, log_size, used_method)
    print('{:02x} {:02x} {:02x} {} {}'.format(
        pri_type, ext_type, log_type, int(geometry_ok), debug))
" 2>/dev/null)

case "$pri_type" in
    01|04|06) ok "MBR entry 1: primary DOS partition type 0x$pri_type" ;;
    *)        fail "MBR entry 1: expected DOS type (01/04/06), got 0x${pri_type:-?}" ;;
esac

if [[ "$ext_type" == "05" ]]; then
    ok "MBR entry 2: extended partition type 0x05"
else
    fail "MBR entry 2: expected type 0x05 (extended), got 0x${ext_type:-?}"
fi

case "$log_type" in
    01|04|06) ok "EBR entry 1: logical drive type 0x$log_type (${ebr_debug:-})" ;;
    *)        fail "EBR entry 1: expected DOS type (01/04/06), got 0x${log_type:-?} (${ebr_debug:-})" ;;
esac

if [[ "$geometry_ok" == "1" ]]; then
    ok "Partition starts, requested sizes, containment, CHS/LBA, and EBR signature are consistent ($ebr_debug)"
else
    fail "Partition geometry does not match the 5 MB primary plus 10 MB logical request ($ebr_debug)"
fi


BOOT_IMG2="$OUT/fdisk-boot2.img"
HDD_IMG2="$OUT/fdisk-hdd2.img"
SERIAL_LOG2="$OUT/fdisk-serial2.log"
BOOT_IMG3="$OUT/fdisk-2g-boot.img"
HDD_IMG3="$OUT/fdisk-2g-hdd.img"
SERIAL_LOG3="$OUT/fdisk-2g-serial.log"
trap 'rm -f "$HDD_IMG" "$HDD_IMG2" "$HDD_IMG3" 2>/dev/null; true' EXIT

echo ""
echo "=== FDISK edge case: primary-only, no extended partition (PTM P941) ==="

echo "Building test image (boot 2)..."
cp "$FLOPPY" "$BOOT_IMG2"
mcopy -o -i "$BOOT_IMG2" "$EXIT_COM" ::QEXIT.COM

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'

    printf 'FDISK 1 /Q\r\n'

    printf 'ECHO ---FDISK_PRIONLY---\r\n'
    printf 'FDISK 1 /PRI:5 /Q\r\n'
    printf 'ECHO FDISK_PRIONLY_DONE\r\n'

    printf 'ECHO ---FDISK_NOEXT---\r\n'
    printf 'FDISK 1 /Q\r\n'
    printf 'IF ERRORLEVEL 2 ECHO FDISK_NOEXT_EL2\r\n'
    printf 'ECHO FDISK_NOEXT_DONE\r\n'

    printf 'ECHO ===DONE2===\r\n'
    printf 'QEXIT.COM\r\n'
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
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        < /dev/null \
        2>/dev/null | tee "$SERIAL_LOG2" > /dev/null; true
}

echo "Booting QEMU (may take ~60s)..."
for attempt in 1 2 3; do
    run_qemu2
    if grep -q "FDISK_NOEXT_DONE" "$SERIAL_LOG2" 2>/dev/null; then
        break
    fi
    echo "  FDISK did not complete (attempt $attempt/3); retrying..."
done

echo ""
echo "--- FDISK primary-only checks ---"

if grep -q "FDISK_PRIONLY_DONE" "$SERIAL_LOG2"; then
    ok "FDISK 1 /PRI:5 /Q (primary-only disk, no extended)"
else
    fail "FDISK 1 /PRI:5 /Q (primary-only: batch hung or crashed)"
fi

if grep -q "FDISK_NOEXT_DONE" "$SERIAL_LOG2"; then
    ok "FDISK 1 /Q on primary-only disk (no crash — PTM P941 guard works)"
else
    fail "FDISK 1 /Q on primary-only disk (crashed — semicolon bug regression?)"
fi

read -r pri2_type ext2_type pri2_geometry_ok pri2_debug < <(python3 -c "
import struct
with open('$HDD_IMG2', 'rb') as f:
    f.seek(446)
    entries = [f.read(16) for _ in range(4)]
    start, size = struct.unpack_from('<II', entries[0], 8)
    size_bytes = size * 512
    clean_tail = all(entry == bytes(16) for entry in entries[1:])
    geometry_ok = start > 0 and 5 * 1024 * 1024 <= size_bytes <= 6 * 1024 * 1024 and clean_tail
    print('{:02x} {:02x} {} start={}:size={}'.format(
        entries[0][4], entries[1][4], int(geometry_ok), start, size))
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

if [[ "$pri2_geometry_ok" == "1" ]]; then
    ok "Primary-only MBR preserves the requested size and zeroes all unused entries ($pri2_debug)"
else
    fail "Primary-only MBR geometry or unused entries are invalid ($pri2_debug)"
fi

if grep -q "===DONE2===" "$SERIAL_LOG2"; then
    ok "Batch 2 reached ===DONE2==="
else
    fail "Batch 2 did NOT reach ===DONE2=== (hung or crashed early)"
    echo "--- last 20 lines of serial log 2 ---"
    tail -20 "$SERIAL_LOG2"
    echo "---"
fi

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "--- full serial log 2 (for debugging) ---"
    cat "$SERIAL_LOG2" 2>/dev/null || echo "(empty)"
    echo "--- end serial log 2 ---"
fi

echo ""
echo "=== FDISK DOS 5 boundary: partition near 2 GiB ==="

cp "$FLOPPY" "$BOOT_IMG3"
mcopy -o -i "$BOOT_IMG3" "$EXIT_COM" ::QEXIT.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'FDISK 1 /PRI:2047 /Q\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FDISK_2G_FAILED\r\n'
    printf 'ECHO FDISK_2G_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG3" - ::AUTOEXEC.BAT

# Keep the large fixture sparse: only the MBR written by FDISK consumes space.
truncate -s 2147483648 "$HDD_IMG3"
timeout 90 qemu-system-i386 \
    -display none -monitor none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG3",cache=writethrough \
    -drive if=ide,index=0,format=raw,file="$HDD_IMG3",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    < /dev/null >"$SERIAL_LOG3" 2>&1 || true

if grep -q 'FDISK_2G_DONE' "$SERIAL_LOG3" \
    && ! grep -q 'FDISK_2G_FAILED' "$SERIAL_LOG3"; then
    ok "FDISK creates a near-2-GiB primary partition without error"
else
    fail "FDISK near-2-GiB creation did not complete successfully"
fi

read -r type3 active3 geometry3 debug3 < <(python3 -c "
import struct
disk_sectors = 2147483648 // 512
with open('$HDD_IMG3', 'rb') as f:
    f.seek(446)
    entry = f.read(16)
start, size = struct.unpack_from('<II', entry, 8)
size_bytes = size * 512
geometry_ok = (
    start > 0
    and 2000 * 1024 * 1024 <= size_bytes <= 2048 * 1024 * 1024
    and start + size <= disk_sectors
    and entry[4] == 0x06
)
print('{:02x} {:02x} {} start={}:size={}'.format(
    entry[4], entry[0], int(geometry_ok), start, size))
" 2>/dev/null)

if [[ "$type3" == "06" && "$active3" == "80" && "$geometry3" == "1" ]]; then
    ok "Near-2-GiB FAT16 partition is active, cylinder-aligned, and within disk bounds ($debug3)"
else
    fail "Near-2-GiB partition table is invalid (type=$type3 active=$active3 $debug3)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
