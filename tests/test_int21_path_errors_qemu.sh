#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/floppy-int21-path-errors.img"
PROBE_COM="$OUT/i21path.com"
SERIAL_LOG="$OUT/int21-path-errors.log"

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

for dos_mode in LOW HIGH; do
cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/int21_path_error_probe.asm" -o "$PROBE_COM"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\nDOS=%s\r\n' "$dos_mode" \
    | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::I21PATH.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'I21PATH.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_LOG"
timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$SERIAL_LOG" 2>&1 || true

if grep -q 'INT21_PATH_ERRORS_PASS' "$SERIAL_LOG"; then
    echo "  PASS: DOS=$dos_mode INT 21h local path, file, nonempty, current-directory, and no-match errors"
    continue
fi
echo "  FAIL: INT 21h path-error probe did not complete"
sed -n '1,160p' "$SERIAL_LOG"
exit 1
done
