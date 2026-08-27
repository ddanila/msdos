#!/bin/bash
# Assert externally visible and documented internal CONFIG.SYS state in QEMU.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/floppy-config-state.img"
PROBE_COM="$OUT/config-state.com"
SERIAL_LOG="$OUT/config-state.log"

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
nasm -f bin "$REPO_ROOT/tests/config_state_probe.asm" -o "$PROBE_COM"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::CFGPROBE.COM
{
    printf 'BREAK=ON\r\n'
    printf 'BUFFERS=20\r\n'
    printf 'FILES=32\r\n'
    printf 'FCBS=8,3\r\n'
    printf 'LASTDRIVE=Z\r\n'
    printf 'COMMENT=BREAK=OFF\r\n'
    printf 'REM BREAK=OFF\r\n'
    printf 'SHELL=COMMAND.COM /P\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'CFGPROBE.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_LOG"
timeout 35 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$SERIAL_LOG" 2>&1 || true

if grep -q 'CONFIG_STATE_PASS' "$SERIAL_LOG"; then
    echo "  PASS: CONFIG.SYS BREAK/BUFFERS/FILES/FCBS/LASTDRIVE/COMMENT/REM contracts"
    exit 0
fi

echo "  FAIL: CONFIG.SYS state contract probe did not complete"
sed -n '1,160p' "$SERIAL_LOG"
exit 1
