#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 BOOTABLE_FAT_IMAGE OUTPUT_LOG" >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE_IMAGE=$1
OUTPUT_LOG=$2
WORK_IMAGE=$(mktemp "${TMPDIR:-/tmp}/msdos-umb-lifecycle.XXXXXX")
PROBE=$(mktemp "${TMPDIR:-/tmp}/msdos-umb-lifecycle-probe.XXXXXX")
EXEC_PROBE=$(mktemp "${TMPDIR:-/tmp}/msdos-umb-exec-probe.XXXXXX")
CHILD=$(mktemp "${TMPDIR:-/tmp}/msdos-umb-child.XXXXXX")
trap 'rm -f "$WORK_IMAGE" "$PROBE" "$EXEC_PROBE" "$CHILD"' EXIT HUP INT TERM

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing required tool: $tool" >&2
        exit 1
    }
done

cp "$SOURCE_IMAGE" "$WORK_IMAGE"
nasm -f bin "$ROOT/tests/umb_lifecycle_reference.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/umb_exec_reference.asm" -o "$EXEC_PROBE"
nasm -f bin "$ROOT/tests/umb_exit_child.asm" -o "$CHILD"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$WORK_IMAGE" "$PROBE" ::UMBLREF.COM
mcopy -o -i "$WORK_IMAGE" "$EXEC_PROBE" ::UMBEXEC.COM
mcopy -o -i "$WORK_IMAGE" "$CHILD" ::UMBCHILD.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'UMBLREF.COM\r\n'
    printf 'UMBEXEC.COM\r\n'
} | mcopy -o -i "$WORK_IMAGE" - ::AUTOEXEC.BAT

mkdir -p "$(dirname "$OUTPUT_LOG")"
timeout 20 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$WORK_IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot >"$OUTPUT_LOG" 2>&1 || true

if ! grep -q '^UMB_LIFECYCLE_END' "$OUTPUT_LOG" \
    || ! grep -q '^UMB_EXEC_PASS SEG=' "$OUTPUT_LOG"
then
    echo "UMB lifecycle reference probe did not complete" >&2
    sed -n '1,160p' "$OUTPUT_LOG" >&2
    exit 1
fi
sed -n '/^UMB_LIFECYCLE_BEGIN/,/^UMB_LIFECYCLE_END/p' "$OUTPUT_LOG"
grep '^UMB_EXEC_PASS SEG=' "$OUTPUT_LOG"
