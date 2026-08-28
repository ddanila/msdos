#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/floppy-xma-drivers.img"
PROBE_COM="$OUT/xma-rejection-probe.com"
SERIAL_LOG="$OUT/xma-drivers-qemu.log"
SCREEN_LOG="$OUT/xma-drivers-screen.log"
QMP_SOCK="$OUT/xma-drivers-qmp.sock"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in nasm mcopy python3 qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

trap 'kill ${QEMU_PID:-} 2>/dev/null; rm -f "$QMP_SOCK" 2>/dev/null; true' EXIT
cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/xma_rejection_probe.asm" -o "$PROBE_COM"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::XMAPROBE.COM
{
    printf 'DEVICE=XMAEM.SYS\r\n'
    printf 'DEVICE=XMA2EMS.SYS\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'XMAPROBE.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$QMP_SOCK" "$SERIAL_LOG" "$SCREEN_LOG"
timeout 45 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -serial file:"$SERIAL_LOG" -no-reboot \
    -qmp unix:"$QMP_SOCK",server,nowait \
    2>/dev/null &
QEMU_PID=$!

for _ in $(seq 1 25); do
    [[ -S "$QMP_SOCK" ]] && break
    sleep 0.2
done
if [[ ! -S "$QMP_SOCK" ]]; then
    echo "ERROR: XMA QMP socket did not appear"
    exit 1
fi

SCREEN_OK=0
if python3 "$REPO_ROOT/tests/screen_expect.py" \
        "$QMP_SOCK" "$SCREEN_LOG" \
        '80386 XMA Emulator not installed. This system unit' '' \
        'is not supported.' '' \
        'Cannot find adapter' '' \
        'Expanded Memory Manager has NOT been installed' ''; then
    SCREEN_OK=1
fi

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true

if [[ "$SCREEN_OK" -eq 1 ]] && grep -q 'XMA_REJECTION_PASS' "$SERIAL_LOG"; then
    echo "  PASS: XMAEM and XMA2EMS emitted exact rejections without leaving resident services"
    exit 0
fi

echo "  FAIL: XMA unsupported-hardware contract did not complete"
sed -n '1,120p' "$SERIAL_LOG"
sed -n '1,180p' "$SCREEN_LOG"
exit 1
