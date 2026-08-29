#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 BOOTABLE_FAT_IMAGE OUTPUT_LOG" >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE_IMAGE=$1
OUTPUT_LOG=$2
WORK_IMAGE=$(mktemp "${TMPDIR:-/tmp}/msdos-umb-mcb.XXXXXX")
PROBE=$(mktemp "${TMPDIR:-/tmp}/msdos-umb-mcb-probe.XXXXXX")
trap 'rm -f "$WORK_IMAGE" "$PROBE"' EXIT HUP INT TERM

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing required tool: $tool" >&2
        exit 1
    }
done

cp "$SOURCE_IMAGE" "$WORK_IMAGE"
nasm -f bin "$ROOT/tests/umb_mcb_layout_probe.asm" -o "$PROBE"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$WORK_IMAGE" "$PROBE" ::UMBMCB.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'UMBMCB.COM\r\n'
} | mcopy -o -i "$WORK_IMAGE" - ::AUTOEXEC.BAT

mkdir -p "$(dirname "$OUTPUT_LOG")"
timeout 20 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$WORK_IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot >"$OUTPUT_LOG" 2>&1 || true

grep -q '^UMB_MCB_LAYOUT_END' "$OUTPUT_LOG" || {
    echo 'UMB MCB layout probe did not complete' >&2
    sed -n '1,180p' "$OUTPUT_LOG" >&2
    exit 1
}
sed -n '/^UMB_MCB_LAYOUT_BEGIN/,/^UMB_MCB_LAYOUT_END/p' "$OUTPUT_LOG"
