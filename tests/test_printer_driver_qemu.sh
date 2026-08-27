#!/bin/bash
# Install PRINTER.SYS and exercise its code-page prepare/select/status path.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
SRC="$REPO_ROOT/MS-DOS/v4.0/src"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/floppy-printer-driver.img"
SERIAL_LOG="$OUT/printer-driver.log"

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
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$SRC/DEV/PRINTER/PRINTER.SYS" ::PRINTER.SYS
mcopy -o -i "$BOOT_IMG" "$SRC/DEV/PRINTER/4201/4201.CPI" ::4201.CPI
printf 'DEVICE=PRINTER.SYS LPT1=(4201,,1)\r\n' \
    | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'MODE LPT1 CP PREPARE=((850) A:\\4201.CPI)\r\n'
    printf 'MODE LPT1 CP SELECT=850\r\n'
    printf 'MODE LPT1 CP /STATUS\r\n'
    printf 'ECHO PRINTER_DRIVER_DONE\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_LOG"
timeout 25 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    >"$SERIAL_LOG" 2>&1 || true

if grep -q 'MODE prepare code page function completed' "$SERIAL_LOG" \
    && grep -q 'MODE select code page function completed' "$SERIAL_LOG" \
    && grep -q 'Active code page for device LPT1 is 850' "$SERIAL_LOG" \
    && grep -q 'code page 850' "$SERIAL_LOG" \
    && grep -q 'PRINTER_DRIVER_DONE' "$SERIAL_LOG"; then
    echo "  PASS: PRINTER.SYS prepared, selected, and reported LPT1 code page 850"
    exit 0
fi

echo "  FAIL: PRINTER.SYS code-page contract did not complete"
sed -n '1,180p' "$SERIAL_LOG"
exit 1
