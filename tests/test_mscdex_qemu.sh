#!/bin/bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/mscdex-test.img"
LOG="$OUT/mscdex-test.log"
DRIVER="$OUT/MSCDDRV.SYS"
PROBE="$OUT/MSCAPI.COM"
EXIT_COM="$OUT/mscdex-qexit.com"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 1; }
done
[[ -f "$BASE" ]] || { echo 'run make deploy first' >&2; exit 1; }

nasm -f bin "$ROOT/tests/mscd_test_driver.asm" -o "$DRIVER"
nasm -f bin "$ROOT/tests/mscdex_api_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
cp "$BASE" "$IMAGE"
mcopy -o -i "$IMAGE" "$ROOT/src/CMD/MSCDEX/MSCDEX.EXE" ::MSCDEX.EXE
mcopy -o -i "$IMAGE" "$DRIVER" ::MSCDDRV.SYS
mcopy -o -i "$IMAGE" "$PROBE" ::MSCAPI.COM
mcopy -o -i "$IMAGE" "$EXIT_COM" ::QEXIT.COM
printf 'DEVICE=A:\\MSCDDRV.SYS /D:MSCD001\r\n' | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'MSCDEX /?\r\nIF NOT ERRORLEVEL 1 ECHO MSCDEX_HELP_STATUS_BAD\r\n'
    printf 'MSCDEX /D:NOTHERE /L:E\r\nIF NOT ERRORLEVEL 1 ECHO MSCDEX_MISSING_ACCEPTED\r\n'
    printf 'MSCDEX /D:MSCD001 /L:E /M:12 /K /S /V\r\n'
    printf 'IF ERRORLEVEL 1 ECHO MSCDEX_INSTALL_FAILED\r\n'
    printf 'MSCAPI.COM\r\nIF ERRORLEVEL 1 ECHO MSCDEX_API_FAILED\r\n'
    printf 'MSCDEX\r\n'
    printf 'ECHO MSCDEX_TEST_DONE\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 30 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true

for marker in \
    "Illegal option '?'" \
    'usage: MSCDEX [/E/K/S/V] [/D:<driver> ... ] [/L:<letter>] [/M:<buffers>]' \
    "Device driver not found: 'NOTHERE'." \
    'No valid CDROM device drivers selected' \
    'MSCDEX Version 2.23' 'Drive assigned to driver: E:' \
    'MSCDEX_API_PASS' 'MSCDEX already installed.' 'MSCDEX_TEST_DONE'; do
    grep -Fq "$marker" "$LOG" || { echo "missing MSCDEX evidence: $marker" >&2; sed -n '1,180p' "$LOG" >&2; exit 1; }
done
if grep -Eq 'MSCDEX_(HELP_STATUS_BAD|MISSING_ACCEPTED|INSTALL_FAILED|API_FAILED)' "$LOG"; then
    sed -n '1,180p' "$LOG" >&2
    exit 1
fi

echo '  PASS: MSCDEX VTOC, metadata, nested directory, read, and driver APIs'
