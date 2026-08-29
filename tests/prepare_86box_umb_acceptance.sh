#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 BUILT_FLOPPY OUTPUT_IMAGE" >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE_IMAGE=$1
OUTPUT_IMAGE=$2
OUT="$ROOT/out"
HIMEM="$OUT/86box-himem.sys"
UMB_PROBE="$OUT/86box-umb-lifecycle.com"
HMA_PROBE="$OUT/86box-hma-reference.com"

for tool in nasm mcopy; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing required tool: $tool" >&2
        exit 1
    }
done

[[ -f "$BASE_IMAGE" ]] || {
    echo "missing built floppy: $BASE_IMAGE" >&2
    exit 1
}
mdir -i "$BASE_IMAGE" ::EMM386.SYS >/dev/null 2>&1 || {
    echo "built floppy does not contain EMM386.SYS: $BASE_IMAGE" >&2
    exit 1
}

mkdir -p "$OUT" "$(dirname "$OUTPUT_IMAGE")"
"$ROOT/bin/jwasm-bin" -Fo"$HIMEM" \
    "$ROOT/MS-DOS/v4.0/src/DEV/HIMEM/HIMEM.ASM"
nasm -f bin "$ROOT/tests/umb_lifecycle_reference.asm" -o "$UMB_PROBE"
nasm -f bin "$ROOT/tests/hma_reference_probe.asm" -o "$HMA_PROBE"

cp "$BASE_IMAGE" "$OUTPUT_IMAGE"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$OUTPUT_IMAGE" "$HIMEM" ::HIMEM.SYS
mcopy -o -i "$OUTPUT_IMAGE" "$UMB_PROBE" ::UMBLREF.COM
mcopy -o -i "$OUTPUT_IMAGE" "$HMA_PROBE" ::HMAREF.COM
{
    printf 'DEVICE=A:\\HIMEM.SYS\r\n'
    printf 'DEVICE=A:\\EMM386.SYS RAM M5\r\n'
    printf 'DOS=HIGH,UMB\r\n'
} | mcopy -o -i "$OUTPUT_IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'IF EXIST RESULT.TXT DEL RESULT.TXT\r\n'
    printf 'UMBLREF.COM > RESULT.TXT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO UMB_FAILED>>RESULT.TXT\r\n'
    printf 'HMAREF.COM >> RESULT.TXT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO HMA_FAILED>>RESULT.TXT\r\n'
    printf 'ECHO CYCLE_ACCEPTANCE_DONE>>RESULT.TXT\r\n'
    printf ':WAIT\r\n'
    printf 'GOTO WAIT\r\n'
} | mcopy -o -i "$OUTPUT_IMAGE" - ::AUTOEXEC.BAT

echo "prepared 86Box UMB/HMA acceptance image: $OUTPUT_IMAGE"
