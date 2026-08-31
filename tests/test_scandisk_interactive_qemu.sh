#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT="$OUT/scandisk-interactive-boot.img"
TARGET="$OUT/scandisk-interactive-target.img"
MOUSE="$OUT/scandisk-mouse.com"
QEXIT="$OUT/scandisk-interactive-qexit.com"
LOG="$OUT/scandisk-interactive.log"

cp "$BASE" "$BOOT"
dd if=/dev/zero of="$TARGET" bs=512 count=2880 status=none
mformat -i "$TARGET" -f 1440 ::
printf 'interactive scandisk payload\r\n' |
    mcopy -o -i "$TARGET" - ::CONTROL.TXT
nasm -f bin "$ROOT/tests/scandisk_mouse_tsr.asm" -o "$MOUSE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
mcopy -o -i "$BOOT" "$ROOT/src/CMD/SCANDISK/SCANDISK.EXE" ::SCANDISK.EXE
mcopy -o -i "$BOOT" "$MOUSE" ::MOUSE.COM
mcopy -o -i "$BOOT" "$QEXIT" ::QEXIT.COM
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nMOUSE.COM\r\nB:\r\n'
    printf 'A:\\SCANDISK.EXE\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SCANDISK_INTERACTIVE_FAILED\r\n'
    printf 'ECHO SCANDISK_INTERACTIVE_RETURNED\r\nA:\\QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT

timeout 35 qemu-system-i386 -display none -monitor none -boot a -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET",cache=writethrough \
    -serial stdio -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$LOG" 2>&1 || true

for marker in \
    'Microsoft ScanDisk' 'Drive B: is ready to be checked.' \
    'Test type: standard; automatic repair: off.' \
    'Test type: thorough surface; automatic repair: on.' \
    'Mouse navigation: available.' 'Checking drive B:' \
    'ScanDisk found no problems.' 'SCANDISK_INTERACTIVE_RETURNED'; do
    grep -Fq "$marker" "$LOG"
done
! grep -Fq SCANDISK_INTERACTIVE_FAILED "$LOG"
payload="$(mcopy -i "$TARGET" ::CONTROL.TXT - 2>/dev/null | tr -d '\r\n')"
[[ "$payload" == 'interactive scandisk payload' ]]

echo '  PASS: ScanDisk full-screen mouse start and current-drive scan'
