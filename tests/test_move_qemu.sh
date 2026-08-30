#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BOOT="$OUT/floppy-move.img"
TARGET="$OUT/floppy-move-target.img"
LOG="$OUT/move.log"
cp "$OUT/floppy.img" "$BOOT"
dd if=/dev/zero bs=512 count=2880 of="$TARGET" status=none
mformat -i "$TARGET" -f 1440 ::
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$OUT/qemu-exit.com"
mcopy -o -i "$BOOT" "$ROOT/src/CMD/MOVE/MOVE.EXE" ::MOVE.EXE
mcopy -o -i "$BOOT" "$OUT/qemu-exit.com" ::QEXIT.COM
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'MD DEST\r\nECHO ONE>ONE.TXT\r\nECHO TWO>TWO.TXT\r\nMOVE /Y ONE.TXT TWO.TXT DEST\r\n'
    printf 'IF EXIST DEST\\ONE.TXT IF EXIST DEST\\TWO.TXT ECHO MOVE_MULTI_PASS\r\n'
    printf 'MD OLD\r\nMD OLD\\SUB\r\nECHO DIRDATA>OLD\\SUB\\DATA.TXT\r\nMOVE OLD NEW\r\n'
    printf 'IF EXIST NEW\\SUB\\DATA.TXT IF NOT EXIST OLD\\NUL ECHO MOVE_RENAME_PASS\r\n'
    printf 'ECHO OLD>TARGET.TXT\r\nECHO NEW>SOURCE.TXT\r\nECHO N>ANSWER.TXT\r\n'
    printf 'MOVE SOURCE.TXT TARGET.TXT <ANSWER.TXT\r\nTYPE TARGET.TXT\r\nIF EXIST SOURCE.TXT ECHO MOVE_DECLINE_PASS\r\n'
    printf 'MOVE /Y SOURCE.TXT TARGET.TXT\r\nTYPE TARGET.TXT\r\nIF NOT EXIST SOURCE.TXT ECHO MOVE_OVERWRITE_PASS\r\n'
    printf 'SET COPYCMD=/Y\r\nECHO POLICY>POLICY.TXT\r\nMOVE POLICY.TXT TARGET.TXT\r\nTYPE TARGET.TXT\r\n'
    printf 'ECHO FORCEOLD>FORCE.TXT\r\nECHO FORCENEW>FSRC.TXT\r\nECHO N>ANSWER.TXT\r\n'
    printf 'MOVE /-Y FSRC.TXT FORCE.TXT <ANSWER.TXT\r\nTYPE FORCE.TXT\r\n'
    printf 'IF EXIST FSRC.TXT ECHO MOVE_MINUS_Y_PASS\r\n'
    printf 'ECHO CROSS>CROSS.TXT\r\nMOVE /Y CROSS.TXT B:\\CROSS.TXT\r\nTYPE B:\\CROSS.TXT\r\n'
    printf 'IF NOT EXIST CROSS.TXT ECHO MOVE_CROSS_FILE_PASS\r\n'
    printf 'MD XDIR\r\nECHO NESTED>XDIR\\NESTED.TXT\r\nMOVE /Y XDIR B:\\XDIR\r\n'
    printf 'TYPE B:\\XDIR\\NESTED.TXT\r\nIF NOT EXIST XDIR\\NUL ECHO MOVE_CROSS_DIR_PASS\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
timeout 30 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true
for marker in MOVE_MULTI_PASS MOVE_RENAME_PASS MOVE_DECLINE_PASS MOVE_OVERWRITE_PASS MOVE_MINUS_Y_PASS MOVE_CROSS_FILE_PASS MOVE_CROSS_DIR_PASS; do
    grep -Fq "$marker" "$LOG"
done
for payload in OLD NEW POLICY FORCEOLD CROSS NESTED; do grep -Fq "$payload" "$LOG"; done
echo '  PASS: MOVE files, directories, overwrite policy, and cross-drive transfers'
