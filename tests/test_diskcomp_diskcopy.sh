#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

BOOT_IMG="$OUT/floppy-diskcomp-boot.img"
TARGET_IMG="$OUT/floppy-diskcomp-target.img"
SERIAL_LOG="$OUT/diskcomp-serial.log"
EXACT_BOOT_IMG="$OUT/diskcopy-exact-source.img"
EXACT_TARGET_IMG="$OUT/diskcopy-exact-target.img"
EXACT_SERIAL_LOG="$OUT/diskcopy-exact-serial.log"
EXIT_COM="$OUT/qemu-exit.com"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

echo "=== DISKCOPY / DISKCOMP E2E tests (QEMU) ==="

echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'

    printf 'ECHO ---DISKCOPY---\r\n'
    printf 'DISKCOPY A: B:\r\n'
    printf 'ECHO DISKCOPY_DONE\r\n'

    printf 'ECHO ---DISKCOMP-MATCH---\r\n'
    printf 'DISKCOMP A: B:\r\n'
    printf 'ECHO DISKCOMP_MATCH_DONE\r\n'

    printf 'ECHO DISKTEST > DISKTEST.TXT\r\n'

    printf 'ECHO ---DISKCOMP-DIFF---\r\n'
    printf 'DISKCOMP A: B:\r\n'
    printf 'ECHO DISKCOMP_DIFF_DONE\r\n'

    printf 'ECHO ---DISKCOPY-1---\r\n'
    printf 'DISKCOPY A: B: /1\r\n'
    printf 'ECHO DISKCOPY_1_DONE\r\n'

    printf 'ECHO ---DISKCOPY-V---\r\n'
    printf 'DISKCOPY A: B: /V\r\n'
    printf 'ECHO DISKCOPY_V_DONE\r\n'

    printf 'ECHO ---DISKCOMP-1---\r\n'
    printf 'DISKCOMP A: B: /1\r\n'
    printf 'ECHO DISKCOMP_1_DONE\r\n'

    printf 'ECHO ---DISKCOMP-8---\r\n'
    printf 'DISKCOMP A: B: /8\r\n'
    printf 'ECHO DISKCOMP_8_DONE\r\n'

    printf 'ECHO ---DISKCOMP-18---\r\n'
    printf 'DISKCOMP A: B: /1 /8\r\n'
    printf 'IF NOT ERRORLEVEL 1 ECHO DISKCOMP_18_SUCCESS\r\n'
    printf 'ECHO DISKCOMP_18_DONE\r\n'

    printf 'DISKCOMP A: B: /1 /1\r\n'
    printf 'IF ERRORLEVEL 1 ECHO DISKCOMP_DUPLICATE_REJECTED\r\n'
    printf 'DISKCOMP A: B: /V\r\n'
    printf 'IF ERRORLEVEL 1 ECHO DISKCOMP_UNKNOWN_REJECTED\r\n'
    printf 'DISKCOMP A: B: C:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO DISKCOMP_ARITY_REJECTED\r\n'
    printf 'DISKCOPY A: B: /1 /1\r\n'
    printf 'IF ERRORLEVEL 1 ECHO DISKCOPY_DUPLICATE_REJECTED\r\n'
    printf 'DISKCOPY A: B: C:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO DISKCOPY_ARITY_REJECTED\r\n'

    printf 'ECHO ===DONE===\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

dd if=/dev/zero bs=512 count=2880 of="$TARGET_IMG" status=none
mformat -i "$TARGET_IMG" -f 1440 ::

echo "Booting QEMU with A:=boot B:=blank target (may take ~90s)..."
rm -f "$SERIAL_LOG"
(while true; do sleep 0.2; printf 'N\r\n'; done) | \
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null | tee "$SERIAL_LOG" > /dev/null; true

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi


echo ""
echo "--- DISKCOPY tests ---"

if grep -qi "Copying.*tracks" "$SERIAL_LOG"; then
    ok "DISKCOPY A: B: (started copying tracks)"
else
    fail "DISKCOPY A: B: (expected 'Copying...tracks' message)"
fi

if grep -qi "Copy another diskette" "$SERIAL_LOG"; then
    ok "DISKCOPY A: B: (copy completed, reached repeat prompt)"
else
    fail "DISKCOPY A: B: (expected 'Copy another diskette' prompt after successful copy)"
fi

if grep -q "DISKCOPY_DONE" "$SERIAL_LOG"; then
    ok "DISKCOPY A: B: (batch continued after DISKCOPY)"
else
    fail "DISKCOPY A: B: (batch hung or crashed after DISKCOPY)"
fi

echo ""
echo "--- DISKCOMP (match) tests ---"

if grep -qi "Comparing.*tracks" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: match (started comparing tracks)"
else
    fail "DISKCOMP A: B: match (expected 'Comparing...tracks' message)"
fi

if grep -qi "Compare OK" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: match (identical disks reported 'Compare OK')"
else
    fail "DISKCOMP A: B: match (expected 'Compare OK' for identical disks)"
fi

if grep -q "DISKCOMP_MATCH_DONE" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: match (batch continued)"
else
    fail "DISKCOMP A: B: match (batch hung or crashed)"
fi

echo ""
echo "--- DISKCOMP (mismatch) tests ---"

if grep -qi "Compare error on" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: mismatch (detected 'Compare error on' after file write)"
else
    fail "DISKCOMP A: B: mismatch (expected 'Compare error on' after DISKTEST.TXT write)"
fi

if grep -q "DISKCOMP_DIFF_DONE" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: mismatch (batch continued)"
else
    fail "DISKCOMP A: B: mismatch (batch hung or crashed)"
fi

echo ""
echo "--- DISKCOPY /1 tests ---"

if grep -qi "1 Side(s)" "$SERIAL_LOG"; then
    ok "DISKCOPY A: B: /1 (single-sided copy: '1 Side(s)' in output)"
else
    fail "DISKCOPY A: B: /1 (expected '1 Side(s)' in Copying message)"
fi

if grep -q "DISKCOPY_1_DONE" "$SERIAL_LOG"; then
    ok "DISKCOPY A: B: /1 (batch continued)"
else
    fail "DISKCOPY A: B: /1 (batch hung or crashed)"
fi

echo ""
echo "--- DISKCOPY /V tests ---"

if grep -qi "Invalid switch" "$SERIAL_LOG"; then
    ok "DISKCOPY A: B: /V (rejected with 'Invalid switch' — /V not implemented in parser)"
else
    fail "DISKCOPY A: B: /V (expected 'Invalid switch' — /V is undocumented stub)"
fi

if grep -q "DISKCOPY_V_DONE" "$SERIAL_LOG"; then
    ok "DISKCOPY A: B: /V (batch continued after error)"
else
    fail "DISKCOPY A: B: /V (batch hung or crashed)"
fi

echo ""
echo "--- DISKCOMP /1 tests ---"

if grep -qi "1 Side(s)" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: /1 (single-sided compare: '1 Side(s)' in output)"
else
    fail "DISKCOMP A: B: /1 (expected '1 Side(s)' in Comparing message)"
fi

if grep -q "DISKCOMP_1_DONE" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: /1 (batch continued)"
else
    fail "DISKCOMP A: B: /1 (batch hung or crashed)"
fi

echo ""
echo "--- DISKCOMP /8 tests ---"

if grep -qi "8 Sectors/Track" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: /8 (8-sector compare: '8 Sectors/Track' in output)"
else
    fail "DISKCOMP A: B: /8 (expected '8 Sectors/Track' in Comparing message)"
fi

if grep -q "DISKCOMP_8_DONE" "$SERIAL_LOG"; then
    ok "DISKCOMP A: B: /8 (batch continued)"
else
    fail "DISKCOMP A: B: /8 (batch hung or crashed)"
fi

echo ""
echo "--- DISKCOMP combined switches and parser boundaries ---"

combined_section="$(sed -n '/---DISKCOMP-18---/,/DISKCOMP_18_DONE/p' "$SERIAL_LOG")"
if grep -q 'DISKCOMP_18_SUCCESS' <<<"$combined_section" \
    && grep -qi '1 Side(s)' <<<"$combined_section" \
    && grep -qi '8 sectors per track' <<<"$combined_section"; then
    ok "DISKCOMP accepts /1 and /8 together and applies both effects"
else
    fail "DISKCOMP did not apply its complete valid switch combination"
fi

if grep -q 'DISKCOMP_DUPLICATE_REJECTED' "$SERIAL_LOG" \
    && grep -q 'DISKCOMP_UNKNOWN_REJECTED' "$SERIAL_LOG" \
    && grep -q 'DISKCOMP_ARITY_REJECTED' "$SERIAL_LOG" \
    && grep -q 'DISKCOPY_DUPLICATE_REJECTED' "$SERIAL_LOG" \
    && grep -q 'DISKCOPY_ARITY_REJECTED' "$SERIAL_LOG" \
    && [[ $(grep -ci 'Invalid switch' "$SERIAL_LOG") -ge 3 ]] \
    && [[ $(grep -ci 'Too many parameters' "$SERIAL_LOG") -ge 2 ]]; then
    ok "DISKCOMP and DISKCOPY reject duplicate, unknown, and excess operands"
else
    fail "DISKCOMP/DISKCOPY parser rejection contracts were incomplete"
fi

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
echo "--- DISKCOPY host-side exact-image verification ---"
cp "$FLOPPY" "$EXACT_BOOT_IMG"
mcopy -o -i "$EXACT_BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'DISKCOPY A: B:\r\n'
    printf 'ECHO DISKCOPY_EXACT_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$EXACT_BOOT_IMG" - ::AUTOEXEC.BAT
dd if=/dev/zero bs=512 count=2880 of="$EXACT_TARGET_IMG" status=none
rm -f "$EXACT_SERIAL_LOG"
(while true; do sleep 0.2; printf 'N\r\n'; done) | \
timeout 45 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$EXACT_BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$EXACT_TARGET_IMG",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null | tee "$EXACT_SERIAL_LOG" >/dev/null; true

if grep -q 'DISKCOPY_EXACT_DONE' "$EXACT_SERIAL_LOG" \
    && copy_detail="$(python3 - "$EXACT_BOOT_IMG" "$EXACT_TARGET_IMG" <<'PY'
import sys

source = bytearray(open(sys.argv[1], 'rb').read())
target = bytearray(open(sys.argv[2], 'rb').read())
assert len(source) == len(target) == 1474560
source_serial = bytes(source[39:43])
target_serial = bytes(target[39:43])
source[39:43] = target[39:43] = b'\0' * 4
assert source == target
assert source_serial != target_serial
print('serial {} -> {}'.format(source_serial.hex(), target_serial.hex()))
PY
)"; then
    ok "DISKCOPY copied every byte and generated only a new volume serial ($copy_detail)"
else
    fail "DISKCOPY changed data outside its documented volume-serial field"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
