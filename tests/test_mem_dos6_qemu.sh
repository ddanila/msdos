#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/mem-dos6.img"
LOG="$OUT/mem-dos6.log"
QEXIT="$OUT/mem-dos6-exit.com"

for tool in mcopy nasm qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done
[[ -f "$BASE" ]] || { echo "ERROR: run make deploy first" >&2; exit 1; }

cp "$BASE" "$IMAGE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
mcopy -o -i "$IMAGE" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
mcopy -o -i "$IMAGE" "$ROOT/src/CMD/MEM/MEM.EXE" ::MEM.EXE
mcopy -o -i "$IMAGE" "$QEXIT" ::QEXIT.COM
{
    printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\n'
    printf 'DOS=HIGH\r\n'
} | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'ECHO CASE=SUMMARY\r\nMEM\r\nECHO CASE_END=SUMMARY\r\n'
    printf 'ECHO CASE=CLASSIFY\r\nMEM /C\r\nECHO CASE_END=CLASSIFY\r\n'
    printf 'ECHO CASE=DEBUG\r\nMEM /D\r\nECHO CASE_END=DEBUG\r\n'
    printf 'ECHO CASE=FREE\r\nMEM /F\r\nECHO CASE_END=FREE\r\n'
    printf 'ECHO CASE=MODULE\r\nMEM /M COMMAND\r\nECHO CASE_END=MODULE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 30 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true

for marker in SUMMARY CLASSIFY DEBUG FREE MODULE; do
    grep -Fq "CASE_END=$marker" "$LOG"
done
for expected in \
    'Type of Memory' 'Conventional' 'Extended (XMS)' 'Total memory' \
    'Total under 1 MB' 'Largest executable program size' \
    'Largest free upper memory block' \
    'MS-DOS is resident in the high memory area.' \
    'Modules using memory below 1 MB:' 'Memory Summary:' \
    'Conventional Memory Detail:' 'Installed Device=HIMEM' \
    'Memory accessible using Int 15h' \
    'XMS version  3.00; driver version  3.16' \
    'Free Conventional Memory:' 'No upper memory available' \
    'COMMAND is using the following memory:' 'Total Size:'
do
    grep -Fq "$expected" "$LOG" || {
        echo "FAIL: MEM DOS 6.22 output missing: $expected" >&2
        strings -a "$LOG" | sed -n '1,300p' >&2
        exit 1
    }
done

echo '  PASS: MEM matches the DOS 6.22 summary, /C, /D, /F, and /M structure'
