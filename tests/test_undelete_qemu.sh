#!/bin/bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT="$OUT/undelete-test-boot.img"
TARGET="$OUT/undelete-test-target.img"
LOG="$OUT/undelete-test.log"
QEXIT="$OUT/undelete-test-qexit.com"
PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

[[ -f "$BASE" ]] || { echo "missing $BASE; run make deploy" >&2; exit 1; }
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
cp "$BASE" "$BOOT"
mcopy -o -i "$BOOT" "$ROOT/src/CMD/UNDELETE/UNDELETE.COM" ::UNDELETE.COM
mcopy -o -i "$BOOT" "$QEXIT" ::QEXIT.COM
printf 'Y\r\nA\r\n' | mcopy -o -i "$BOOT" - ::ANSWERS.TXT

dd if=/dev/zero of="$TARGET" bs=512 count=2880 status=none
mformat -i "$TARGET" -f 1440 ::
printf 'ROOT INTERACTIVE PAYLOAD\r\n' | mcopy -i "$TARGET" - ::ALPHA.TXT
mmd -i "$TARGET" ::SUB
printf 'NESTED EXACT PAYLOAD\r\n' | mcopy -i "$TARGET" - ::SUB/NESTED.DAT
printf 'COLLISION PAYLOAD\r\n' | mcopy -i "$TARGET" - '::SUB/#ESTED.DAT'

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'DEL B:\\ALPHA.TXT\r\n'
    printf 'DEL B:\\SUB\\NESTED.DAT\r\n'
    printf 'UNDELETE B:\\*.TXT /LIST /DOS\r\n'
    printf 'IF ERRORLEVEL 1 ECHO LIST_FAILED\r\n'
    printf 'UNDELETE B:\\ALPHA.TXT /DOS < A:\\ANSWERS.TXT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO INTERACTIVE_FAILED\r\n'
    printf 'B:\r\n'
    printf 'CD \\SUB\r\n'
    printf 'A:\r\n'
    printf 'UNDELETE B:*.DAT /ALL\r\n'
    printf 'IF ERRORLEVEL 1 ECHO NESTED_FAILED\r\n'
    printf 'ECHO UNDELETE_TEST_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT

timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$LOG" 2>&1 || true

if grep -q '?LPHA.TXT  26 bytes' "$LOG" && ! grep -q 'LIST_FAILED' "$LOG"; then
    ok "/LIST reports the deleted DOS directory entry"
else
    fail "/LIST contract"
fi
if grep -q 'Restored ALPHA.TXT' "$LOG" && ! grep -q 'INTERACTIVE_FAILED' "$LOG"; then
    ok "/DOS accepts an interactive first character"
else
    fail "/DOS interactive recovery"
fi
if grep -q 'Restored %ESTED.DAT' "$LOG" && ! grep -q 'NESTED_FAILED' "$LOG"; then
    ok "/ALL uses the next collision-free replacement in a current subdirectory"
else
    fail "/ALL nested recovery"
fi

root_payload="$(mcopy -i "$TARGET" ::ALPHA.TXT - 2>/dev/null | tr -d '\r\n')"
nested_payload="$(mcopy -i "$TARGET" '::SUB/%ESTED.DAT' - 2>/dev/null | tr -d '\r\n')"
if [[ "$root_payload" == 'ROOT INTERACTIVE PAYLOAD' ]]; then
    ok "interactive recovery preserves the exact root payload"
else
    fail "root payload mismatch"
fi
if [[ "$nested_payload" == 'NESTED EXACT PAYLOAD' ]]; then
    ok "automatic recovery preserves the exact nested payload"
else
    fail "nested payload mismatch"
fi

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
