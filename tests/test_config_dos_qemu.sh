#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/floppy-config-dos.img"
SERIAL_LOG="$OUT/config-dos.log"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in mcopy qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

cp "$FLOPPY" "$BOOT_IMG"
{
    printf 'dos=umb,low\r\n'
    printf 'DOS=HIGH,NOUMB\r\n'
    printf 'DOS=LOW,UMB\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'ECHO CONFIG_DOS_PASS\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_LOG"
timeout 35 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    >"$SERIAL_LOG" 2>&1 || true

if grep -q '^CONFIG_DOS_PASS' "$SERIAL_LOG"; then
    echo "  PASS: DOS= accepts case-insensitive HIGH/LOW and UMB/NOUMB combinations"
    exit 0
fi

echo "  FAIL: DOS= CONFIG.SYS combinations did not reach AUTOEXEC.BAT"
sed -n '1,100p' "$SERIAL_LOG"
exit 1
