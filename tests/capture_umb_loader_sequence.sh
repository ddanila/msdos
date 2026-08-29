#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 BOOTABLE_FAT_IMAGE OUTPUT_LOG" >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE_IMAGE=$1
OUTPUT_LOG=$2
WORK_IMAGE=$(mktemp "${TMPDIR:-/tmp}/msdos-umb-loader.XXXXXX")
PROBE=$(mktemp "${TMPDIR:-/tmp}/msdos-umb-loader-probe.XXXXXX")
trap 'rm -f "$WORK_IMAGE" "$PROBE"' EXIT HUP INT TERM

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing required tool: $tool" >&2
        exit 1
    }
done

cp "$SOURCE_IMAGE" "$WORK_IMAGE"
nasm -f bin "$ROOT/tests/umb_loader_sequence_probe.asm" -o "$PROBE"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$WORK_IMAGE" "$PROBE" ::UMBLOAD.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'UMBLOAD.COM\r\n'
} | mcopy -o -i "$WORK_IMAGE" - ::AUTOEXEC.BAT

mkdir -p "$(dirname "$OUTPUT_LOG")"
rm -f "$OUTPUT_LOG"
timeout 20 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$WORK_IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot >"$OUTPUT_LOG" 2>&1 || true

if ! grep -q '^UMB_LOADER_SEQUENCE_END' "$OUTPUT_LOG"; then
    echo "UMB loader sequence probe did not complete" >&2
    sed -n '1,160p' "$OUTPUT_LOG" >&2
    exit 1
fi

sed -n '/^UMB_LOADER_SEQUENCE_BEGIN/,/^UMB_LOADER_SEQUENCE_END/p' "$OUTPUT_LOG"
