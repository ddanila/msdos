#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo 'usage: capture_hma_fallback_reference.sh BOOTABLE_FAT_IMAGE OUTPUT_LOG' >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE_IMAGE=$1
OUTPUT_LOG=$2
WORK_IMAGE=$(mktemp "${TMPDIR:-/tmp}/msdos-hma-fallback.XXXXXX")
QMP_SOCKET=$(mktemp -u "${TMPDIR:-/tmp}/msdos-hma-fallback-qmp.XXXXXX")
QEMU_PID=
cleanup() {
    if [[ -n "$QEMU_PID" ]]; then
        kill "$QEMU_PID" 2>/dev/null || true
        wait "$QEMU_PID" 2>/dev/null || true
    fi
    rm -f "$WORK_IMAGE" "$QMP_SOCKET"
}
trap cleanup EXIT HUP INT TERM

for tool in mcopy qemu-system-i386 python3 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing required tool: $tool" >&2
        exit 1
    }
done

cp "$SOURCE_IMAGE" "$WORK_IMAGE"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
printf 'DOS=HIGH\r\n' | mcopy -o -i "$WORK_IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'PROMPT HMA_FALLBACK_READY$G\r\n'
} | mcopy -o -i "$WORK_IMAGE" - ::AUTOEXEC.BAT

mkdir -p "$(dirname "$OUTPUT_LOG")"
rm -f "$QMP_SOCKET" "$OUTPUT_LOG"
qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$WORK_IMAGE",cache=writethrough \
    -boot a -qmp unix:"$QMP_SOCKET",server,nowait -no-reboot \
    >/dev/null 2>&1 &
QEMU_PID=$!

for _ in $(seq 1 50); do
    [[ -S "$QMP_SOCKET" ]] && break
    kill -0 "$QEMU_PID" 2>/dev/null || break
    sleep 0.1
done
[[ -S "$QMP_SOCKET" ]] || {
    echo 'QMP socket did not appear' >&2
    exit 1
}

timeout 30 python3 "$ROOT/tests/screen_expect.py" \
    "$QMP_SOCKET" "$OUTPUT_LOG" 'HMA_FALLBACK_READY>' ''
grep -Fq 'HMA_FALLBACK_READY>' "$OUTPUT_LOG" || {
    echo 'reference image did not reach the DOS prompt' >&2
    sed -n '1,160p' "$OUTPUT_LOG" >&2
    exit 1
}

sed -n '/=== Rule 0:/,/=== Final screen ===/p' "$OUTPUT_LOG"
