#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/xcopy-dos6.img"
EXIT_COM="$OUT/xcopy-dos6-qexit.com"
SERIAL="$OUT/xcopy-dos6-serial.log"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
cp "$BASE" "$IMAGE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$IMAGE" "$EXIT_COM" ::QEXIT.COM
for dir in SRC DSTY DSTN DSTENV DSTOVR ATTRSRC ATTRDST; do mmd -i "$IMAGE" "::$dir"; done
printf 'NEW\r\n' | mcopy -o -i "$IMAGE" - ::SRC/FILE.TXT
printf 'OLD\r\n' | mcopy -o -i "$IMAGE" - ::DSTY/FILE.TXT
printf 'OLD\r\n' | mcopy -o -i "$IMAGE" - ::DSTN/FILE.TXT
printf 'OLD\r\n' | mcopy -o -i "$IMAGE" - ::DSTENV/FILE.TXT
printf 'OLD\r\n' | mcopy -o -i "$IMAGE" - ::DSTOVR/FILE.TXT
printf 'N\r\n' | mcopy -o -i "$IMAGE" - ::NO.IN
printf 'VISIBLE\r\n' | mcopy -o -i "$IMAGE" - ::ATTRSRC/VISIBLE.TXT
printf 'HIDDEN\r\n' | mcopy -o -i "$IMAGE" - ::ATTRSRC/HIDDEN.TXT
printf 'SYSTEM\r\n' | mcopy -o -i "$IMAGE" - ::ATTRSRC/SYSTEM.TXT
mattrib -i "$IMAGE" +h ::ATTRSRC/HIDDEN.TXT
mattrib -i "$IMAGE" +s ::ATTRSRC/SYSTEM.TXT

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'XCOPY A:\\SRC\\FILE.TXT A:\\DSTY\\ /Y\r\n'
    printf 'XCOPY A:\\SRC\\FILE.TXT A:\\DSTN\\ /-Y < A:\\NO.IN\r\n'
    printf 'SET COPYCMD=/Y\r\n'
    printf 'XCOPY A:\\SRC\\FILE.TXT A:\\DSTENV\\\r\n'
    printf 'SET COPYCMD=/-Y\r\n'
    printf 'XCOPY A:\\SRC\\FILE.TXT A:\\DSTOVR\\ /Y\r\n'
    printf 'XCOPY A:\\ATTRSRC\\*.* A:\\ATTRDST\\\r\n'
    printf 'ECHO XCOPY_DOS6_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

set +e
timeout 30 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    2>/dev/null | tee "$SERIAL" >/dev/null
set -e

grep -Fq XCOPY_DOS6_DONE "$SERIAL"
mtype -i "$IMAGE" ::DSTY/FILE.TXT | grep -Fq NEW
mtype -i "$IMAGE" ::DSTN/FILE.TXT | grep -Fq OLD
for dir in DSTENV DSTOVR; do mtype -i "$IMAGE" "::$dir/FILE.TXT" | grep -Fq NEW; done
mtype -i "$IMAGE" ::ATTRDST/VISIBLE.TXT | grep -Fq VISIBLE
! mdir -i "$IMAGE" ::ATTRDST/HIDDEN.TXT >/dev/null 2>&1
! mdir -i "$IMAGE" ::ATTRDST/SYSTEM.TXT >/dev/null 2>&1
echo '  PASS: XCOPY /Y, /-Y, COPYCMD precedence, and hidden/system exclusion'
