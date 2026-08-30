#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo 'usage: capture_mem_reference.sh MSDOS_622_BOOTABLE_IMAGE OUTPUT_LOG' >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE_IMAGE=$1
OUTPUT_LOG=$2
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/msdos-mem-reference.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing required tool: $tool" >&2
        exit 1
    }
done

nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$WORK_DIR/QEXIT.COM"
cp "$SOURCE_IMAGE" "$WORK_DIR/mem-reference.img"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$WORK_DIR/mem-reference.img" "$WORK_DIR/QEXIT.COM" ::QEXIT.COM
{
    printf 'DEVICE=A:\HIMEM.SYS /TESTMEM:OFF\r\n'
    printf 'DEVICE=A:\EMM386.EXE NOEMS X=D000-D7FF\r\n'
    printf 'DOS=HIGH,UMB\r\n'
} | mcopy -o -i "$WORK_DIR/mem-reference.img" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'IF NOT EXIST A:\\MEM.EXE A:\\EXPAND A:\\MEM.EX_ A:\\MEM.EXE > NUL\r\n'
    printf 'ECHO MEM_REFERENCE_BEGIN DOS=6.22\r\n'
    printf 'ECHO CASE=SUMMARY\r\nMEM\r\nECHO CASE_END=SUMMARY\r\n'
    printf 'ECHO CASE=CLASSIFY\r\nMEM /C\r\nECHO CASE_END=CLASSIFY\r\n'
    printf 'ECHO CASE=DEBUG\r\nMEM /D\r\nECHO CASE_END=DEBUG\r\n'
    printf 'ECHO CASE=FREE\r\nMEM /F\r\nECHO CASE_END=FREE\r\n'
    printf 'ECHO CASE=MODULE\r\nMEM /M COMMAND\r\nECHO CASE_END=MODULE\r\n'
    printf 'ECHO MEM_REFERENCE_END DOS=6.22\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$WORK_DIR/mem-reference.img" - ::AUTOEXEC.BAT

timeout 45 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$WORK_DIR/mem-reference.img",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$WORK_DIR/mem-reference.log" 2>&1 || true

if ! grep -Fq 'MEM_REFERENCE_END DOS=6.22' "$WORK_DIR/mem-reference.log"; then
    echo 'reference capture did not complete' >&2
    strings -a "$WORK_DIR/mem-reference.log" | sed -n '1,240p' >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_LOG")"
strings -a "$WORK_DIR/mem-reference.log" \
    | sed -n '/MEM_REFERENCE_BEGIN DOS=6.22/,/MEM_REFERENCE_END DOS=6.22/p' \
    >"$OUTPUT_LOG"
cat "$OUTPUT_LOG"
