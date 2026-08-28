#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/floppy-graphics-print.img"
SERIAL_LOG="$OUT/graphics-print.log"
PARALLEL_LOG="$OUT/graphics-print-lpt1.bin"
PROBE_COM="$OUT/graphics-print-probe.com"
EXIT_COM="$OUT/graphics-print-exit.com"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in mcopy nasm python3 qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/graphics_print_probe.asm" -o "$PROBE_COM"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"

export MTOOLS_NO_VFAT=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::GRPROBE.COM
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'GRAPHICS /LCD /PB:STD\r\n'
    printf 'GRAPHICS /PB:STD /LCD\r\n'
    printf 'GRAPHICS /LCD /LCD\r\n'
    printf 'GRAPHICS /PB:STD /PRINTBOX:STD\r\n'
    printf 'GRAPHICS /R /R\r\n'
    printf 'GRAPHICS /B /B\r\n'
    printf 'GRAPHICS /Z\r\n'
    printf 'GRAPHICS GRAPHICS GRAPHICS.PRO /PB:STD\r\n'
    printf 'IF ERRORLEVEL 1 ECHO GRAPHICS_INSTALL_FAILED\r\n'
    printf 'GRPROBE.COM\r\n'
    printf 'IF ERRORLEVEL 1 ECHO GRAPHICS_PROBE_FAILED\r\n'
    printf 'ECHO GRAPHICS_PRINT_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_LOG" "$PARALLEL_LOG"
timeout 20 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -parallel "file:$PARALLEL_LOG" \
    -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -boot a -no-reboot \
    >"$SERIAL_LOG" 2>&1 || true

analysis="$(python3 - "$PARALLEL_LOG" <<'PY'
from pathlib import Path
import hashlib
import sys

data = Path(sys.argv[1]).read_bytes() if Path(sys.argv[1]).exists() else b""
print(len(data), hashlib.sha256(data).hexdigest(), data.count(b"\x1bL"))
PY
)"

if [[ $(grep -c '^Invalid parameter combination' "$SERIAL_LOG") -eq 2 ]] \
    && [[ $(grep -c '^Duplicate parameters not allowed' "$SERIAL_LOG") -eq 4 ]] \
    && grep -Fq 'Invalid parameter:   /Z' "$SERIAL_LOG" \
    && grep -q 'GRAPHICS_PRINT_DONE' "$SERIAL_LOG" \
    && ! grep -q 'GRAPHICS_.*_FAILED\|Printer error' "$SERIAL_LOG"; then
    read -r capture_size capture_sha graphics_blocks <<<"$analysis"
    if [[ "$capture_size" == 17781 \
        && "$capture_sha" == 8afd0de4bd00fb51325256f281fdec5b7ed51644f01c4eb9b91f4bc550f60506 \
        && "$graphics_blocks" == 25 ]]; then
        echo "  PASS: GRAPHICS rejected parser conflicts and emitted the exact LPT1 stream"
        exit 0
    fi
fi

echo "  FAIL: GRAPHICS resident Print Screen contract did not complete"
sed -n '1,180p' "$SERIAL_LOG"
echo "GRAPHICS capture: $analysis"
exit 1
