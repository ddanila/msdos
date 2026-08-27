#!/bin/bash
# Assert DOS 4 media-ID get/set behavior against a disposable B: image.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"
BOOT_IMG="$OUT/floppy-int21-media.img"
TARGET_IMG="$OUT/floppy-int21-media-target.img"
PROBE_COM="$OUT/i21media.com"
SERIAL_LOG="$OUT/int21-media.log"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in nasm mcopy mformat mlabel qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

cp "$FLOPPY" "$BOOT_IMG"
dd if=/dev/zero bs=512 count=2880 of="$TARGET_IMG" status=none
mformat -i "$TARGET_IMG" -f 1440 ::
nasm -f bin "$REPO_ROOT/tests/int21_media_probe.asm" -o "$PROBE_COM"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::I21MEDIA.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'I21MEDIA.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

rm -f "$SERIAL_LOG"
timeout 35 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET_IMG",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$SERIAL_LOG" 2>&1 || true

label_output="$(mlabel -i "$TARGET_IMG" -s :: 2>/dev/null || true)"
raw_label="$(dd if="$TARGET_IMG" bs=1 skip=43 count=11 status=none)"
if grep -q 'INT21_MEDIA_PASS' "$SERIAL_LOG" && \
   [[ "$raw_label" == I21MEDIA* ]]; then
    echo "  PASS: INT 21h media ID readback and raw-image metadata update"
    exit 0
fi

echo "  FAIL: INT 21h media-ID contract probe did not complete"
sed -n '1,180p' "$SERIAL_LOG"
echo "  host label: $label_output"
echo "  boot-sector label: $raw_label"
exit 1
