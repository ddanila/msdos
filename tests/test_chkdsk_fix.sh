#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

BOOT_IMG="$OUT/chkdsk-boot.img"
TARGET_IMG="$OUT/chkdsk-target.img"
SERIAL_LOG="$OUT/chkdsk-fix-serial.log"
EXIT_COM="$OUT/qemu-exit.com"
SERIAL_IN="$OUT/chkdsk-fix-serial.in"
SERIAL_OUT="$OUT/chkdsk-fix-serial.out"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'rm -f "$SERIAL_IN" "$SERIAL_OUT" 2>/dev/null; true' EXIT

echo "=== CHKDSK /F E2E tests (QEMU, interactive serial expect) ==="

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM

dd if=/dev/zero of="$TARGET_IMG" bs=512 count=2880 status=none
mformat -i "$TARGET_IMG" ::

printf 'Hello from CHKDSK test\r\n' | mcopy -o -i "$TARGET_IMG" - ::CHKTEST.TXT

echo "Corrupting FAT to create orphan clusters..."
python3 -c "
import struct

with open('$TARGET_IMG', 'r+b') as f:
    def read_fat12(fat_off, cluster):
        byte_off = fat_off + (cluster * 3) // 2
        f.seek(byte_off)
        word = struct.unpack('<H', f.read(2))[0]
        if cluster % 2 == 0:
            return word & 0xFFF
        else:
            return (word >> 4) & 0xFFF

    def write_fat12(fat_off, cluster, value):
        byte_off = fat_off + (cluster * 3) // 2
        f.seek(byte_off)
        word = struct.unpack('<H', f.read(2))[0]
        if cluster % 2 == 0:
            word = (word & 0xF000) | (value & 0xFFF)
        else:
            word = (word & 0x000F) | ((value & 0xFFF) << 4)
        f.seek(byte_off)
        f.write(struct.pack('<H', word))

    FAT1_OFF = 512
    FAT2_OFF = 512 * 10

    for c in [100, 101, 102]:
        v = read_fat12(FAT1_OFF, c)
        assert v == 0, f'Cluster {c} already in use: 0x{v:03X}'

    for fat_off in [FAT1_OFF, FAT2_OFF]:
        write_fat12(fat_off, 100, 101)
        write_fat12(fat_off, 101, 102)
        write_fat12(fat_off, 102, 0xFFF)

    DATA_OFF = 33 * 512
    for cluster in [100, 101, 102]:
        f.seek(DATA_OFF + (cluster - 2) * 512)
        f.write(bytes((cluster + index) & 0xFF for index in range(512)))

    for fat_off in [FAT1_OFF, FAT2_OFF]:
        assert read_fat12(fat_off, 100) == 101
        assert read_fat12(fat_off, 101) == 102
        assert read_fat12(fat_off, 102) == 0xFFF

    print('FAT corrupted: orphan chain 100 -> 101 -> 102 -> EOF in FAT1+FAT2')
" || { echo "ERROR: FAT corruption script failed"; exit 1; }

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'

    printf 'ECHO ---CHKDSK-FIX---\r\n'
    printf 'CHKDSK B: /F\r\n'
    printf 'ECHO CHKDSK_FIX_DONE\r\n'

    printf 'ECHO ---CHKDSK-VERIFY---\r\n'
    printf 'DIR B:\\FILE0000.CHK\r\n'
    printf 'ECHO CHKDSK_VERIFY_DONE\r\n'

    printf 'ECHO ---CHKDSK-CLEAN---\r\n'
    printf 'CHKDSK B:\r\n'
    printf 'ECHO CHKDSK_CLEAN_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_IN" "$SERIAL_OUT"
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
# Holding the input FIFO as O_RDWR prevents either endpoint from blocking during startup.
exec 3<>"$SERIAL_IN"

echo "Booting QEMU with CHKDSK /F test..."
rm -f "$SERIAL_LOG"
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial pipe:"$OUT/chkdsk-fix-serial" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null &
QEMU_PID=$!

python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$SERIAL_LOG" \
    "Convert lost chains to files" 'Y\r'

wait $QEMU_PID || true
exec 3>&-

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

echo ""
echo "--- CHKDSK /F (fix) ---"

if grep -q "CHKDSK_FIX_DONE" "$SERIAL_LOG"; then
    ok "CHKDSK B: /F completed (fix mode)"
else
    fail "CHKDSK B: /F (batch hung or crashed — prompt not answered?)"
fi

if grep -qi "Convert lost chains" "$SERIAL_LOG"; then
    ok "CHKDSK /F prompted 'Convert lost chains to files'"
else
    fail "CHKDSK /F (expected 'Convert lost chains' prompt)"
fi

if grep -qi "lost.*allocation unit\|lost cluster" "$SERIAL_LOG"; then
    ok "CHKDSK /F detected lost allocation units"
else
    fail "CHKDSK /F (expected 'lost allocation units' in output)"
fi

if grep -qi "recovered file" "$SERIAL_LOG"; then
    ok "CHKDSK /F reported recovered files"
else
    fail "CHKDSK /F (expected 'recovered file' in output)"
fi

echo ""
echo "--- Verification ---"

if grep -q "CHKDSK_VERIFY_DONE" "$SERIAL_LOG"; then
    ok "DIR B:\\FILE0000.CHK completed"
else
    fail "DIR B:\\FILE0000.CHK (batch hung or crashed)"
fi

if grep -qi "FILE0000.*CHK" "$SERIAL_LOG"; then
    ok "FILE0000.CHK exists on B: (orphan chain recovered to file)"
else
    fail "FILE0000.CHK not found on B: (recovery may have failed)"
fi

expected_recovered_hash="$(python3 -c "
import hashlib
data = b''.join(bytes((cluster + index) & 0xff for index in range(512)) for cluster in (100, 101, 102))
print(hashlib.sha256(data).hexdigest())
")"
actual_recovered_hash="$(mtype -i "$TARGET_IMG" ::FILE0000.CHK 2>/dev/null \
    | sha256sum | awk '{print $1}')"
if [[ "$actual_recovered_hash" == "$expected_recovered_hash" ]]; then
    ok "CHKDSK /F preserved all three orphan-cluster payloads exactly"
else
    fail "FILE0000.CHK payload hash differs from the injected orphan chain"
fi

control_contents="$(mtype -i "$TARGET_IMG" ::CHKTEST.TXT 2>/dev/null | tr -d '\r' || true)"
if [[ "$control_contents" == 'Hello from CHKDSK test' ]]; then
    ok "CHKDSK /F preserved the referenced control file"
else
    fail "CHKDSK /F changed the referenced control file: '$control_contents'"
fi

echo ""
echo "--- Post-fix verification (CHKDSK B: without /F) ---"

if grep -q "CHKDSK_CLEAN_DONE" "$SERIAL_LOG"; then
    ok "CHKDSK B: (post-fix) completed"
else
    fail "CHKDSK B: (post-fix batch hung or crashed)"
fi

if grep -q "CHKDSK_CLEAN_DONE" "$SERIAL_LOG" && \
   ! sed -n '/---CHKDSK-CLEAN---/,/CHKDSK_CLEAN_DONE/p' "$SERIAL_LOG" | grep -qi "lost.*allocation unit\|Errors found"; then
    ok "CHKDSK B: (post-fix) reports clean disk — no errors"
else
    fail "CHKDSK B: (post-fix) still reports errors after fix"
fi

echo ""
if grep -q "===DONE===" "$SERIAL_LOG"; then
    ok "Batch reached ===DONE==="
else
    fail "Batch did NOT reach ===DONE=== (hung or crashed early)"
    echo "--- last 30 lines of serial log ---"
    tail -30 "$SERIAL_LOG"
    echo "---"
fi

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "--- full serial log (for debugging) ---"
    cat "$SERIAL_LOG" 2>/dev/null || echo "(empty)"
    echo "--- end serial log ---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
