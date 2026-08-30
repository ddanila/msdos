#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/config-set.img"
SERIAL="$OUT/config-set.log"
EXIT_COM="$OUT/config-set-qexit.com"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool"
        exit 1
    }
done

nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
cp "$BASE" "$IMAGE"
{
    printf 'SET FOO=FIRST\r\n'
    printf 'SET FOO=SECOND\r\n'
    printf 'SET SPACE=HELLO WORLD\r\n'
    printf 'SET DROP=\r\n'
} | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'ECHO FOO=[%%FOO%%]\r\n'
    printf 'ECHO SPACE=[%%SPACE%%]\r\n'
    printf 'ECHO DROP=[%%DROP%%]\r\n'
    printf 'SET\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT
mcopy -o -i "$IMAGE" "$EXIT_COM" ::QEXIT.COM

set +e
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null | tee "$SERIAL" >/dev/null
set -e

grep -Fq 'FOO=[SECOND]' "$SERIAL"
grep -Fq 'SPACE=[HELLO WORLD]' "$SERIAL"
grep -Fq 'DROP=[]' "$SERIAL"
[[ $(grep -c '^FOO=SECOND' "$SERIAL") -eq 1 ]]
! grep -q '^FOO=FIRST' "$SERIAL"
! grep -q '^DROP=' "$SERIAL"
echo '  PASS: CONFIG.SYS SET values reach AUTOEXEC and later assignments win'
