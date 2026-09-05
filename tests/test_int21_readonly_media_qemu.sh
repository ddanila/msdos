#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/floppy-int21-readonly-media.img"
TARGET_IMG="$OUT/floppy-int21-readonly-media-target.img"
PROBE_COM="$OUT/i21romed.com"
SERIAL_LOG="$OUT/int21-readonly-media.log"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in nasm mcopy mformat qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

for dos_mode in LOW HIGH; do
cp "$FLOPPY" "$BOOT_IMG"
dd if=/dev/zero bs=512 count=2880 of="$TARGET_IMG" status=none
mformat -i "$TARGET_IMG" -f 1440 ::
nasm -f bin "$REPO_ROOT/tests/int21_readonly_media_probe.asm" -o "$PROBE_COM"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\nDOS=%s\r\n' "$dos_mode" \
    | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::I21ROMED.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'I21ROMED.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_LOG"
timeout 35 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET_IMG",readonly=on \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$SERIAL_LOG" 2>&1 || true

if grep -q 'INT21_READONLY_MEDIA_PASS' "$SERIAL_LOG"; then
    echo "  PASS: DOS=$dos_mode INT 21h write-protected media access errors"
    continue
fi

echo "  FAIL: INT 21h read-only-media contract probe did not complete"
sed -n '1,180p' "$SERIAL_LOG"
exit 1
done
