#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || ($2 != HIGH && $2 != LOW) ]]; then
    echo 'usage: capture_hma_reference.sh BOOTABLE_FAT_IMAGE HIGH|LOW OUTPUT_LOG' >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE_IMAGE=$1
MODE=$2
OUTPUT_LOG=$3
WORK_IMAGE=$(mktemp "${TMPDIR:-/tmp}/msdos-hma-reference.XXXXXX")
PROBE=$(mktemp "${TMPDIR:-/tmp}/msdos-hma-probe.XXXXXX")
CONFIG=$(mktemp "${TMPDIR:-/tmp}/msdos-hma-config.XXXXXX")
trap 'rm -f "$WORK_IMAGE" "$PROBE" "$CONFIG"' EXIT HUP INT TERM

for tool in nasm mcopy mtype qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing required tool: $tool" >&2
        exit 1
    }
done

cp "$SOURCE_IMAGE" "$WORK_IMAGE"
nasm -f bin "$ROOT/tests/hma_reference_probe.asm" -o "$PROBE"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mtype -i "$WORK_IMAGE" ::CONFIG.SYS \
    | awk '{ sub(/\r$/, ""); if (toupper($0) !~ /^DOS=/) printf "%s\r\n", $0 }' \
        >"$CONFIG"
printf 'DOS=%s,UMB\r\n' "$MODE" >>"$CONFIG"
mcopy -o -i "$WORK_IMAGE" "$CONFIG" ::CONFIG.SYS
mcopy -o -i "$WORK_IMAGE" "$PROBE" ::HMAREF.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'HMAREF.COM\r\n'
} | mcopy -o -i "$WORK_IMAGE" - ::AUTOEXEC.BAT

mkdir -p "$(dirname "$OUTPUT_LOG")"
timeout 20 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$WORK_IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot >"$OUTPUT_LOG" 2>&1 || true

if ! grep -q '^HMA_REFERENCE_END' "$OUTPUT_LOG"; then
    echo 'HMA reference probe did not complete' >&2
    sed -n '1,180p' "$OUTPUT_LOG" >&2
    exit 1
fi
grep -E '^(A20|HMA_REQUEST|LARGEST_LOW|DOS_VERSION|HMA_REFERENCE_END)' "$OUTPUT_LOG"
