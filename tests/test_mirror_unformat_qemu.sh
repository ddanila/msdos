#!/bin/bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT="$OUT/recovery-test-boot.img"
TARGET="$OUT/recovery-test-target.img"
HDD="$OUT/recovery-test-hdd.img"
LOG="$OUT/recovery-test.log"
PART_LOG="$OUT/recovery-partition-test.log"
QEXIT="$OUT/recovery-test-qexit.com"
PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

[[ -f "$BASE" ]] || { echo "missing $BASE; run make deploy" >&2; exit 1; }
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
cp "$BASE" "$BOOT"
mcopy -o -i "$BOOT" "$ROOT/src/CMD/MIRROR/MIRROR.COM" ::MIRROR.COM
mcopy -o -i "$BOOT" "$ROOT/src/CMD/UNFORMAT/UNFORMAT.COM" ::UNFORMAT.COM
mcopy -o -i "$BOOT" "$QEXIT" ::QEXIT.COM

dd if=/dev/zero of="$TARGET" bs=512 count=2880 status=none
mformat -i "$TARGET" -f 1440 ::
printf 'RECOVERY EXACT PAYLOAD\r\n' | mcopy -i "$TARGET" - ::KEEP.TXT
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'MIRROR B:\r\n'
    printf 'FORMAT B: /Q /AUTOTEST\r\n'
    printf 'UNFORMAT B: /J\r\n'
    printf 'IF ERRORLEVEL 1 ECHO VERIFY_FAILED\r\n'
    printf 'ECHO Y|UNFORMAT B:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESTORE_FAILED\r\n'
    printf 'IF EXIST B:\\KEEP.TXT ECHO RECOVERY_FILE_PRESENT\r\n'
    printf 'ECHO RECOVERY_TEST_DONE\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$LOG" 2>&1 || true

if grep -q 'Complete recovery information found for drive B:' "$LOG" &&
   grep -q 'RECOVERY_FILE_PRESENT' "$LOG" &&
   ! grep -Eq 'VERIFY_FAILED|RESTORE_FAILED' "$LOG"; then
    ok "MIRROR metadata survives quick FORMAT and passes /J"
else
    fail "MIRROR/UNFORMAT workflow"
fi
payload="$(mcopy -i "$TARGET" ::KEEP.TXT - 2>/dev/null | tr -d '\r\n')"
if [[ "$payload" == 'RECOVERY EXACT PAYLOAD' ]]; then
    ok "UNFORMAT restores the exact FAT/root file payload"
else
    fail "UNFORMAT payload mismatch"
fi

cp "$OUT/format-hdd-template.img" "$HDD"
dd if="$HDD" of="$OUT/recovery-test-mbr-before.bin" bs=512 count=1 status=none
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nMIRROR /PARTN\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PARTITION_SAVE_FAILED\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=ide,index=0,format=raw,file="$HDD",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$PART_LOG" 2>&1 || true
dd if=/dev/zero of="$HDD" bs=1 seek=446 count=64 conv=notrunc status=none
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nUNFORMAT /PARTN /L\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PARTITION_LIST_FAILED\r\n'
    printf 'ECHO Y|UNFORMAT /PARTN\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PARTITION_RESTORE_FAILED\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=ide,index=0,format=raw,file="$HDD",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >>"$PART_LOG" 2>&1 || true
dd if="$HDD" of="$OUT/recovery-test-mbr-after.bin" bs=512 count=1 status=none
if cmp -s "$OUT/recovery-test-mbr-before.bin" "$OUT/recovery-test-mbr-after.bin" &&
   ! grep -Eq 'PARTITION_(SAVE|LIST|RESTORE)_FAILED' "$PART_LOG"; then
    ok "/PARTN validates geometry and restores the exact MBR"
else
    fail "/PARTN workflow"
fi

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
