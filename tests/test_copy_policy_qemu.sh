#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/copy-policy.img"
EXIT_COM="$OUT/copy-policy-qexit.com"
SERIAL="$OUT/copy-policy-serial.log"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
cp "$BASE" "$IMAGE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$IMAGE" "$EXIT_COM" ::QEXIT.COM
printf 'N\r\n' | mcopy -o -i "$IMAGE" - ::NO.IN
printf 'NEW\r\n' | mcopy -o -i "$IMAGE" - ::SRC.TXT
for name in Y N ENV OVERRIDE; do
    printf 'OLD\r\n' | mcopy -o -i "$IMAGE" - "::$name.TXT"
done

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'COPY /Y SRC.TXT Y.TXT\r\n'
    printf 'COPY /-Y SRC.TXT N.TXT < NO.IN\r\n'
    printf 'SET COPYCMD=/Y\r\n'
    printf 'COPY SRC.TXT ENV.TXT\r\n'
    printf 'SET COPYCMD=/-Y\r\n'
    printf 'COPY /Y SRC.TXT OVERRIDE.TXT\r\n'
    printf 'ECHO COPY_POLICY_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

set +e
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null | tee "$SERIAL" >/dev/null
set -e

grep -Fq COPY_POLICY_DONE "$SERIAL"
for name in Y ENV OVERRIDE; do
    mtype -i "$IMAGE" "::$name.TXT" | grep -Fq NEW
done
mtype -i "$IMAGE" ::N.TXT | grep -Fq OLD
echo '  PASS: COPY /Y, /-Y, COPYCMD, and command-line precedence'
