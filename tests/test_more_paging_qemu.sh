#!/bin/bash
# Verify MORE's real console paging boundary and lossless resume behavior.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/more-paging-boot.img"
TEXT_FILE="$OUT/more-paging-input.txt"
EXIT_COM="$OUT/more-paging-qexit.com"
SERIAL_LOG="$OUT/more-paging-serial.log"
SERIAL_IN="$OUT/more-paging-serial.in"
SERIAL_OUT="$OUT/more-paging-serial.out"

PASS=0
FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'kill ${QEMU_PID:-} 2>/dev/null; rm -f "$SERIAL_IN" "$SERIAL_OUT" 2>/dev/null; true' EXIT

echo "=== MORE console paging test (QEMU serial console) ==="

cp "$FLOPPY" "$BOOT_IMG"
{
    for line in $(seq 1 60); do
        printf 'PAGE_LINE_%03d\r\n' "$line"
    done
} > "$TEXT_FILE"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$TEXT_FILE" ::MORETEST.TXT
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'ECHO MORE_BEGIN\r\n'
    printf 'MORE ^< MORETEST.TXT\r\n'
    printf 'ECHO MORE_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_IN" "$SERIAL_OUT" "$SERIAL_LOG"
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"

timeout 30 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG" \
    -boot a -m 4 \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -serial pipe:"$OUT/more-paging-serial" \
    2>/dev/null &
QEMU_PID=$!

python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$SERIAL_LOG" \
    '-- More --' '\x00\x4d' \
    '-- More --' 'x'

wait "$QEMU_PID" || true
exec 3>&-

echo ""
echo "--- MORE paging assertions ---"

prompt_count=$(grep -c -- '-- More --' "$SERIAL_LOG" || true)
if [[ "$prompt_count" -eq 2 ]]; then
    ok "exactly two page-boundary prompts for 60 lines"
else
    fail "expected two page-boundary prompts, got $prompt_count"
fi

actual_sequence=$(grep -o 'PAGE_LINE_[0-9][0-9][0-9]' "$SERIAL_LOG" | tr '\n' ' ')
expected_sequence=""
for line in $(seq 1 60); do
    expected_sequence+=$(printf 'PAGE_LINE_%03d ' "$line")
done
if [[ "$actual_sequence" == "$expected_sequence" ]]; then
    ok "ordinary and extended keys resumed all 60 lines exactly once and in order"
else
    fail "line sequence was lost, duplicated, or reordered across a page boundary"
fi

if grep -q 'MORE_BEGIN' "$SERIAL_LOG" && grep -q 'MORE_DONE' "$SERIAL_LOG"; then
    ok "MORE returned normally after the final page"
else
    fail "MORE did not complete and return to the batch"
fi

if [[ $FAIL -gt 0 ]]; then
    echo "--- serial log ---"
    cat "$SERIAL_LOG"
    echo "--- end serial log ---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
