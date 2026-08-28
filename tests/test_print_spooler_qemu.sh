#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/floppy-print-spooler.img"
SERIAL_LOG="$OUT/print-spooler.log"
PARALLEL_LOG="$OUT/print-spooler-lpt1.bin"
WAIT_COM="$OUT/print-queue-wait.com"
EXIT_COM="$OUT/print-spooler-exit.com"

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
nasm -f bin "$REPO_ROOT/tests/print_queue_wait.asm" -o "$WAIT_COM"
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"

export MTOOLS_NO_VFAT=1
mcopy -o -i "$BOOT_IMG" "$WAIT_COM" ::PWAIT.COM
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
printf 'PRINT_PAYLOAD_ALPHA\r\nPRINT_PAYLOAD_OMEGA\r\n' \
    | mcopy -o -i "$BOOT_IMG" - ::PAYLOAD.TXT
printf 'DEVICE=PRINTER.SYS LPT1=(4201,,1)\r\n' \
    | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'PRINT /B:511\r\n'
    printf 'PRINT /B:16385\r\n'
    printf 'PRINT /Q:3\r\n'
    printf 'PRINT /Q:33\r\n'
    printf 'PRINT /S:0\r\n'
    printf 'PRINT /U:256\r\n'
    printf 'PRINT /M:0\r\n'
    printf 'PRINT /Z\r\n'
    printf 'PRINT /B:512 /B:512\r\n'
    printf 'PRINT /D:LPT1 /B:512 /Q:5 /S:1 /U:1 /M:1\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PRINT_INSTALL_FAILED\r\n'
    printf 'PRINT PAYLOAD.TXT /P\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PRINT_QUEUE_FAILED\r\n'
    printf 'PWAIT.COM\r\n'
    printf 'IF ERRORLEVEL 1 ECHO PRINT_WAIT_FAILED\r\n'
    printf 'PRINT\r\n'
    printf 'ECHO PRINT_SPOOL_DONE\r\n'
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

expected="$OUT/print-spooler-expected.bin"
python3 - "$expected" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b"PRINT_PAYLOAD_ALPHA\r\nPRINT_PAYLOAD_OMEGA\r\n\f")
PY

rejections_complete=1
expected_diagnostics=(
    'Parameter value not in allowed range -  /B:511'
    'Parameter value not in allowed range -  /B:16385'
    'Parameter value not in allowed range -  /Q:3'
    'Parameter value not in allowed range -  /Q:33'
    'Parameter value not in allowed range -  /S:0'
    'Parameter value not in allowed range -  /U:256'
    'Parameter value not in allowed range -  /M:0'
    'Invalid switch -  /Z'
    'Invalid switch - /B:512'
)
for diagnostic in "${expected_diagnostics[@]}"; do
    grep -Fq -- "$diagnostic" "$SERIAL_LOG" || rejections_complete=0
done

if [[ $rejections_complete -eq 1 ]] \
    && [[ $(grep -c 'Parameter value not in allowed range' "$SERIAL_LOG") -eq 7 ]] \
    && [[ $(grep -c 'Invalid switch' "$SERIAL_LOG") -eq 2 ]] \
    && [[ $(grep -c 'Resident part of PRINT installed' "$SERIAL_LOG") -eq 1 ]] \
    && grep -q 'PRINT_SPOOL_DONE' "$SERIAL_LOG" \
    && grep -q 'PRINT queue is empty' "$SERIAL_LOG" \
    && ! grep -q 'PRINT_.*_FAILED' "$SERIAL_LOG" \
    && cmp -s "$expected" "$PARALLEL_LOG"; then
    echo "  PASS: PRINT rejected parser boundaries before delivering the exact queued payload"
    exit 0
fi

echo "  FAIL: PRINT/PRINTER.SYS spooler contract did not complete"
sed -n '1,180p' "$SERIAL_LOG"
if [[ -f "$PARALLEL_LOG" ]]; then
    echo "Captured LPT1 bytes: $(wc -c < "$PARALLEL_LOG" | tr -d ' ')"
    od -An -tx1 "$PARALLEL_LOG" | head -12
fi
exit 1
