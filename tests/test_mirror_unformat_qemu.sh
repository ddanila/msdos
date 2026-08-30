#!/bin/bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT="$OUT/recovery-test-boot.img"
TARGET="$OUT/recovery-test-target.img"
UNSAFE_TARGET="$OUT/recovery-test-unsafe-target.img"
REBUILD_TARGET="$OUT/recovery-test-rebuild-target.img"
PRIOR_TARGET="$OUT/recovery-test-prior-target.img"
HDD="$OUT/recovery-test-hdd.img"
LOG="$OUT/recovery-test.log"
UNSAFE_LOG="$OUT/recovery-test-unsafe.log"
REBUILD_LOG="$OUT/recovery-test-rebuild.log"
PRIOR_LOG="$OUT/recovery-test-prior.log"
PRINT_LOG="$OUT/recovery-test-printer.log"
PART_LOG="$OUT/recovery-partition-test.log"
QEXIT="$OUT/recovery-test-qexit.com"
PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

erase_floppy_fats() {
    local image="$1"
    dd if=/dev/zero of="$image" bs=1 seek=515 count=4605 conv=notrunc status=none
    dd if=/dev/zero of="$image" bs=1 seek=5123 count=4605 conv=notrunc status=none
}

[[ -f "$BASE" ]] || { echo "missing $BASE; run make deploy" >&2; exit 1; }
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
cp "$BASE" "$BOOT"
mcopy -o -i "$BOOT" "$ROOT/src/CMD/FORMAT/FORMAT.COM" ::FORMAT.COM
mcopy -o -i "$BOOT" "$ROOT/src/CMD/MIRROR/MIRROR.COM" ::MIRROR.COM
mcopy -o -i "$BOOT" "$ROOT/src/CMD/UNFORMAT/UNFORMAT.COM" ::UNFORMAT.COM
mcopy -o -i "$BOOT" "$QEXIT" ::QEXIT.COM

dd if=/dev/zero of="$TARGET" bs=512 count=2880 status=none
mformat -i "$TARGET" -f 1440 ::
printf 'RECOVERY EXACT PAYLOAD\r\n' | mcopy -i "$TARGET" - ::KEEP.TXT
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
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

if grep -q 'Recovery information saved for drive B:' "$LOG" &&
   grep -q 'Complete recovery information found for drive B:' "$LOG" &&
   grep -q 'RECOVERY_FILE_PRESENT' "$LOG" &&
   ! grep -Eq 'VERIFY_FAILED|RESTORE_FAILED' "$LOG"; then
    ok "safe FORMAT records recovery metadata and UNFORMAT /J validates it"
else
    fail "MIRROR/UNFORMAT workflow"
fi

dd if=/dev/zero of="$UNSAFE_TARGET" bs=512 count=2880 status=none
mformat -i "$UNSAFE_TARGET" -f 1440 ::
printf 'DESTRUCTIVE FORMAT PAYLOAD\r\n' | mcopy -i "$UNSAFE_TARGET" - ::ERASED.TXT
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'FORMAT B: /U /AUTOTEST\r\n'
    printf 'UNFORMAT B: /J\r\n'
    printf 'IF ERRORLEVEL 1 ECHO UNCONDITIONAL_NOT_RECOVERABLE\r\n'
    printf 'IF EXIST B:\\ERASED.TXT ECHO UNCONDITIONAL_FILE_PRESENT\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 35 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$UNSAFE_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$UNSAFE_LOG" 2>&1 || true
if grep -q 'UNCONDITIONAL_NOT_RECOVERABLE' "$UNSAFE_LOG" &&
   ! grep -q 'UNCONDITIONAL_FILE_PRESENT' "$UNSAFE_LOG" &&
   ! grep -aq 'MSD5REC' "$UNSAFE_TARGET"; then
    ok "FORMAT /U bypasses recovery metadata and is not recoverable"
else
    fail "FORMAT /U recovery exclusion"
fi
payload="$(mcopy -i "$TARGET" ::KEEP.TXT - 2>/dev/null | tr -d '\r\n')"
if [[ "$payload" == 'RECOVERY EXACT PAYLOAD' ]]; then
    ok "UNFORMAT restores the exact FAT/root file payload"
else
    fail "UNFORMAT payload mismatch"
fi

dd if=/dev/zero of="$PRIOR_TARGET" bs=512 count=2880 status=none
mformat -i "$PRIOR_TARGET" -f 1440 ::
printf 'PRIOR GENERATION PAYLOAD\r\n' | mcopy -i "$PRIOR_TARGET" - ::PRIOR.TXT
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nMIRROR B:\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$PRIOR_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$PRIOR_LOG" 2>&1 || true
mren -i "$PRIOR_TARGET" ::PRIOR.TXT ::LATEST.TXT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$PRIOR_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >>"$PRIOR_LOG" 2>&1 || true
dd if=/dev/zero of="$PRIOR_TARGET" bs=512 seek=1 count=32 conv=notrunc status=none
printf 'P\r\nY\r\n' | mcopy -o -i "$BOOT" - ::CHOICE.TXT
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nUNFORMAT B: <CHOICE.TXT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PRIOR_RESTORE_FAILED\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$PRIOR_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >>"$PRIOR_LOG" 2>&1 || true
prior_payload="$(mcopy -i "$PRIOR_TARGET" ::PRIOR.TXT - 2>/dev/null | tr -d '\r\n')"
if grep -q 'Latest mirror:' "$PRIOR_LOG" &&
   grep -q 'Prior mirror:' "$PRIOR_LOG" &&
   [[ "$prior_payload" == 'PRIOR GENERATION PAYLOAD' ]] &&
   ! mdir -i "$PRIOR_TARGET" ::LATEST.TXT >/dev/null 2>&1 &&
   ! grep -q 'PRIOR_RESTORE_FAILED' "$PRIOR_LOG"; then
    ok "UNFORMAT selects and exactly restores the prior mirror generation"
else
    fail "UNFORMAT prior-generation selection"
fi

dd if=/dev/zero of="$REBUILD_TARGET" bs=512 count=2880 status=none
mformat -i "$REBUILD_TARGET" -f 1440 ::
for unused in 1 2 3 4 5 6 7 8; do
    printf 'FORENSIC RECONSTRUCTION PAYLOAD %s\r\n' "$unused"
done | mcopy -i "$REBUILD_TARGET" - ::FORENSIC.TXT
erase_floppy_fats "$REBUILD_TARGET"
before_test="$(dd if="$REBUILD_TARGET" bs=512 count=19 status=none | shasum -a 256)"
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nUNFORMAT B: /TEST\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FORENSIC_TEST_FAILED\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$REBUILD_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$REBUILD_LOG" 2>&1 || true
after_test="$(dd if="$REBUILD_TARGET" bs=512 count=19 status=none | shasum -a 256)"
if [[ "$before_test" == "$after_test" ]] &&
   grep -q 'Test completed; the disk was not changed.' "$REBUILD_LOG" &&
   ! grep -q 'FORENSIC_TEST_FAILED' "$REBUILD_LOG"; then
    ok "UNFORMAT /TEST performs a read-only mirror-independent reconstruction"
else
    fail "UNFORMAT /TEST dry run"
fi

{
    printf '@ECHO OFF\r\nCTTY AUX\r\nUNFORMAT B: /TEST /P\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
: >"$PRINT_LOG"
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$REBUILD_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio -parallel "file:$PRINT_LOG" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >>"$REBUILD_LOG" 2>&1 || true
if grep -q 'Test completed; the disk was not changed.' "$PRINT_LOG"; then
    ok "UNFORMAT /P sends reconstruction output to LPT1"
else
    fail "UNFORMAT /P printer output"
fi

{
    printf '@ECHO OFF\r\nCTTY AUX\r\nUNFORMAT B: /L\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FORENSIC_LIST_FAILED\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$REBUILD_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >>"$REBUILD_LOG" 2>&1 || true
rebuild_payload="$(mcopy -i "$REBUILD_TARGET" ::FORENSIC.TXT - 2>/dev/null | tr -d '\r\n')"
if grep -q 'FORENSIC.TXT' "$REBUILD_LOG" &&
   [[ "$rebuild_payload" == *'FORENSIC RECONSTRUCTION PAYLOAD 8' ]] &&
   ! grep -q 'FORENSIC_LIST_FAILED' "$REBUILD_LOG"; then
    ok "UNFORMAT /L lists records and rebuilds an exact contiguous chain"
else
    fail "UNFORMAT /L reconstruction"
fi

erase_floppy_fats "$REBUILD_TARGET"
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nUNFORMAT B: /U\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FORENSIC_U_FAILED\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$REBUILD_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >>"$REBUILD_LOG" 2>&1 || true
rebuild_payload="$(mcopy -i "$REBUILD_TARGET" ::FORENSIC.TXT - 2>/dev/null | tr -d '\r\n')"
if [[ "$rebuild_payload" == *'FORENSIC RECONSTRUCTION PAYLOAD 8' ]] &&
   ! grep -q 'FORENSIC_U_FAILED' "$REBUILD_LOG"; then
    ok "UNFORMAT /U ignores mirror data and rebuilds the exact file chain"
else
    fail "UNFORMAT /U reconstruction"
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
