#!/usr/bin/env bash
# Verify DISPLAY.SYS pass-through behavior above ANSI.SYS and BIOS CON.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/floppy-display-chain.img"
PROBE_COM="$OUT/display-chain.com"
SERIAL_LOG="$OUT/display-chain.log"
SCREEN_LOG="$OUT/display-chain-screen.log"
QMP_SOCK="$OUT/display-chain-qmp.sock"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in nasm mcopy qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/display_chain_probe.asm" -o "$PROBE_COM"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::DSPPRB.COM
{
    printf 'DEVICE=ANSI.SYS\r\n'
    printf 'DEVICE=DISPLAY.SYS CON=(EGA,,1)\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'DSPPRB.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

trap 'kill ${QEMU_PID:-} 2>/dev/null; rm -f "$QMP_SOCK" 2>/dev/null; true' EXIT
rm -f "$SERIAL_LOG" "$SCREEN_LOG" "$QMP_SOCK"
timeout 35 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -serial file:"$SERIAL_LOG" -no-reboot \
    -qmp unix:"$QMP_SOCK",server,nowait \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null &
QEMU_PID=$!

python3 "$REPO_ROOT/tests/screen_expect.py" \
    "$QMP_SOCK" "$SCREEN_LOG" \
    'DISPLAY_READ_READY' 'r' \
    'DISPLAY_RDND_READY' 'n' \
    'DISPLAY_FLUSH_READY' 'f'

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true

if grep -q 'DISPLAY_CHAIN_PASS' "$SERIAL_LOG"; then
    echo "  PASS: DISPLAY.SYS chained output, input, flush, and exact request statuses"
    exit 0
fi

echo "  FAIL: DISPLAY.SYS chain contract did not complete"
sed -n '1,120p' "$SERIAL_LOG"
exit 1
