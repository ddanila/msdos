#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

BOOT_IMG="$OUT/label-boot.img"
TARGET_IMG="$OUT/label-target.img"
SERIAL_LOG="$OUT/label-serial.log"
SERIAL_IN="$OUT/label-serial.in"
SERIAL_OUT="$OUT/label-serial.out"
EXIT_COM="$OUT/qemu-exit.com"
BOUNDARY_BOOT="$OUT/label-boundary-boot.img"
BOUNDARY_TARGET="$OUT/label-boundary-target.img"
BOUNDARY_LOG="$OUT/label-boundary-serial.log"
BOUNDARY_IN="$OUT/label-boundary-serial.in"
BOUNDARY_OUT="$OUT/label-boundary-serial.out"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'rm -f "$SERIAL_IN" "$SERIAL_OUT" "$OUT/label-set-serial.in" "$OUT/label-set-serial.out" "$BOUNDARY_IN" "$BOUNDARY_OUT" 2>/dev/null; true' EXIT

echo "=== LABEL E2E tests (QEMU, interactive serial expect) ==="

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM

dd if=/dev/zero bs=512 count=2880 of="$TARGET_IMG" status=none
mformat -i "$TARGET_IMG" -f 1440 ::
mlabel  -i "$TARGET_IMG" ::TESTLABEL

prelabel=$(mlabel -i "$TARGET_IMG" -s :: 2>/dev/null || echo "")
if ! echo "$prelabel" | grep -qi "TESTLABEL"; then
    echo "ERROR: failed to pre-write label 'TESTLABEL' to target — got: '$prelabel'"
    exit 1
fi
echo "  Pre-test label on B: '$prelabel'"

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'ECHO ---LABEL-REMOVE---\r\n'
    printf 'LABEL B:\r\n'
    printf 'ECHO LABEL_DONE\r\n'
    printf 'ECHO ===DONE===\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

mkfifo "$SERIAL_IN" "$SERIAL_OUT"
# Holding the input FIFO as O_RDWR prevents either endpoint from blocking during startup.
exec 3<>"$SERIAL_IN"

echo "Booting QEMU with interactive LABEL test..."
rm -f "$SERIAL_LOG"
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial pipe:"$OUT/label-serial" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null &
QEMU_PID=$!

python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$SERIAL_LOG" \
    "ENTER for none"              $'\\r' \
    "Delete current volume label" 'Y'

wait $QEMU_PID || true
exec 3>&-

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

echo ""
echo "--- LABEL serial log checks ---"

if grep -q "LABEL_DONE" "$SERIAL_LOG"; then
    ok "LABEL B: (batch continued after LABEL)"
else
    fail "LABEL B: (batch hung or crashed after LABEL)"
fi

if grep -qi "ENTER for none" "$SERIAL_LOG"; then
    ok "LABEL B: (label prompt appeared in serial log)"
else
    fail "LABEL B: (label prompt not seen — CTTY AUX routing issue?)"
fi

if grep -qi "Delete current volume label" "$SERIAL_LOG"; then
    ok "LABEL B: (delete confirmation prompt appeared)"
else
    fail "LABEL B: (delete prompt not seen — empty label may not have triggered it)"
fi

if grep -q "===DONE===" "$SERIAL_LOG"; then
    ok "Batch reached ===DONE==="
else
    fail "Batch did NOT reach ===DONE=== (hung or crashed early)"
    echo "--- last 20 lines of serial log ---"
    tail -20 "$SERIAL_LOG"
    echo "---"
fi

echo ""
echo "--- LABEL post-QEMU image check ---"

postlabel=$(mlabel -i "$TARGET_IMG" -s :: 2>/dev/null || echo "")
if echo "$postlabel" | grep -qi "TESTLABEL"; then
    fail "LABEL remove (label 'TESTLABEL' still present: '$postlabel')"
else
    ok "LABEL remove (label cleared — mlabel output: '$postlabel')"
fi

echo ""
echo "--- LABEL set test (interactive) ---"

dd if=/dev/zero bs=512 count=2880 of="$TARGET_IMG" status=none
mformat -i "$TARGET_IMG" -f 1440 ::

prelabel2=$(mlabel -i "$TARGET_IMG" -s :: 2>/dev/null || echo "")
echo "  Pre-test label on B: '$prelabel2'"

BOOT_IMG2="$OUT/label-set-boot.img"
SERIAL_LOG2="$OUT/label-set-serial.log"
SERIAL_IN2="$OUT/label-set-serial.in"
SERIAL_OUT2="$OUT/label-set-serial.out"
cp "$FLOPPY" "$BOOT_IMG2"
mcopy -o -i "$BOOT_IMG2" "$EXIT_COM" ::QEXIT.COM

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'ECHO ---LABEL-SET---\r\n'
    printf 'LABEL B:\r\n'
    printf 'ECHO LABEL_SET_DONE\r\n'
    printf 'ECHO ===DONE===\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG2" - ::AUTOEXEC.BAT

rm -f "$SERIAL_IN2" "$SERIAL_OUT2"
mkfifo "$SERIAL_IN2" "$SERIAL_OUT2"
exec 4<>"$SERIAL_IN2"

echo "Booting QEMU for LABEL set test..."
rm -f "$SERIAL_LOG2"
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG2",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial pipe:"$OUT/label-set-serial" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null &
QEMU_PID2=$!

python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$SERIAL_IN2" "$SERIAL_OUT2" "$SERIAL_LOG2" \
    "ENTER for none"  $'NEWLABEL\\r'

wait $QEMU_PID2 || true
exec 4>&-
rm -f "$SERIAL_IN2" "$SERIAL_OUT2"

if [[ ! -f "$SERIAL_LOG2" || ! -s "$SERIAL_LOG2" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

echo ""
echo "--- LABEL set serial log checks ---"

if grep -q "LABEL_SET_DONE" "$SERIAL_LOG2"; then
    ok "LABEL B: NEWLABEL (batch continued after LABEL)"
else
    fail "LABEL B: NEWLABEL (batch hung or crashed)"
fi

if grep -q "===DONE===" "$SERIAL_LOG2"; then
    ok "LABEL set: batch reached ===DONE==="
else
    fail "LABEL set: batch did NOT reach ===DONE==="
fi

echo ""
echo "--- LABEL set post-QEMU image check ---"

postlabel2=$(mlabel -i "$TARGET_IMG" -s :: 2>/dev/null || echo "")
if echo "$postlabel2" | grep -qi "NEWLABEL"; then
    ok "LABEL set (label 'NEWLABEL' written to B: — mlabel output: '$postlabel2')"
else
    fail "LABEL set (expected 'NEWLABEL' on B:, got: '$postlabel2')"
fi

rm -f "$BOOT_IMG2"

echo ""
echo "--- LABEL command-line boundary test ---"
cp "$FLOPPY" "$BOUNDARY_BOOT"
mcopy -o -i "$BOUNDARY_BOOT" "$EXIT_COM" ::QEXIT.COM
dd if=/dev/zero bs=512 count=2880 of="$BOUNDARY_TARGET" status=none
mformat -i "$BOUNDARY_TARGET" -f 1440 ::
mlabel -i "$BOUNDARY_TARGET" ::OLDLABEL
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'LABEL B:ABCDEFGHIJKL\r\n'
    printf 'ECHO LABEL_LONG_DONE\r\n'
    printf 'LABEL B:BAD*LABEL\r\n'
    printf 'ECHO LABEL_BOUNDARY_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOUNDARY_BOOT" - ::AUTOEXEC.BAT
rm -f "$BOUNDARY_LOG" "$BOUNDARY_IN" "$BOUNDARY_OUT"
mkfifo "$BOUNDARY_IN" "$BOUNDARY_OUT"
exec 5<>"$BOUNDARY_IN"
timeout 25 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOUNDARY_BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$BOUNDARY_TARGET",cache=writethrough \
    -boot a -m 4 -serial pipe:"$OUT/label-boundary-serial" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null &
QEMU_PID3=$!
python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$BOUNDARY_IN" "$BOUNDARY_OUT" "$BOUNDARY_LOG" \
    'ENTER for none' $'\r' \
    'Delete current volume label' 'N'
wait "$QEMU_PID3" 2>/dev/null || true
exec 5>&-
boundary_label="$(mlabel -i "$BOUNDARY_TARGET" -s :: 2>/dev/null || true)"
if grep -q 'LABEL_LONG_DONE' "$BOUNDARY_LOG" \
    && grep -qi 'Invalid characters in volume label' "$BOUNDARY_LOG" \
    && grep -q 'LABEL_BOUNDARY_DONE' "$BOUNDARY_LOG" \
    && grep -qi 'ABCDEFGHIJK' <<<"$boundary_label" \
    && ! grep -qi 'BAD.*LABEL' <<<"$boundary_label"; then
    ok "LABEL truncates at 11 characters and preserves it after invalid input"
else
    fail "LABEL command-line boundary contract failed: '$boundary_label'"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
