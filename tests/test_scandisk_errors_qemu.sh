#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
TARGET="$OUT/scandisk-errors-target.img"
PRISTINE="$OUT/scandisk-errors-pristine.img"
BOOT="$OUT/scandisk-errors-boot.img"
FAULT="$OUT/scandisk-errors-fault.com"
QEXIT="$OUT/scandisk-errors-qexit.com"

nasm -f bin "$ROOT/tests/scandisk_int13_fault_tsr.asm" -o "$FAULT"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"

dd if=/dev/zero of="$PRISTINE" bs=512 count=2880 status=none
mformat -i "$PRISTINE" -f 1440 ::
printf 'persistent I/O fault control payload\r\n' |
    mcopy -o -i "$PRISTINE" - ::CONTROL.TXT

run_case() {
    local mode="$1" command="$2" log="$3"
    cp "$BASE" "$BOOT"
    cp "$PRISTINE" "$TARGET"
    mcopy -o -i "$BOOT" "$ROOT/src/CMD/SCANDISK/SCANDISK.EXE" ::SCANDISK.EXE
    mcopy -o -i "$BOOT" "$FAULT" ::FAULT.COM
    mcopy -o -i "$BOOT" "$QEXIT" ::QEXIT.COM
    {
        printf '@ECHO OFF\r\nCTTY AUX\r\n'
        printf 'FAULT.COM %s\r\n' "$mode"
        printf '%s\r\n' "$command"
        printf 'IF ERRORLEVEL 255 ECHO LEVEL_255\r\n'
        printf 'IF ERRORLEVEL 254 ECHO LEVEL_254\r\n'
        printf 'IF ERRORLEVEL 4 ECHO LEVEL_4\r\n'
        printf 'IF ERRORLEVEL 3 ECHO LEVEL_3\r\n'
        printf 'IF ERRORLEVEL 2 ECHO LEVEL_2\r\n'
        printf 'IF ERRORLEVEL 1 ECHO LEVEL_1\r\n'
        printf 'ECHO CASE_DONE\r\nQEXIT.COM\r\n'
    } | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
    timeout 45 qemu-system-i386 -display none -monitor none -boot a -m 4 \
        -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
        -drive if=floppy,index=1,format=raw,file="$TARGET",cache=writethrough \
        -serial stdio -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        </dev/null >"$log" 2>&1 || true
    grep -Fq 'CASE_DONE' "$log"
}

READ_LOG="$OUT/scandisk-error-read.log"
run_case R 'SCANDISK B: /CHECKONLY /NOSUMMARY' "$READ_LOG"
grep -Fq 'A file allocation table cannot be read.' "$READ_LOG"
grep -Fq 'ScanDisk was stopped after a physical disk read failure.' "$READ_LOG"
grep -Fq 'LEVEL_3' "$READ_LOG"
! grep -Fq 'LEVEL_4' "$READ_LOG"
! grep -Fq 'Lost clusters were found.' "$READ_LOG"
cmp -s "$TARGET" "$PRISTINE"

WRITE_LOG="$OUT/scandisk-error-write.log"
run_case W 'SCANDISK B: /CHECKONLY /SURFACE /NOSUMMARY' "$WRITE_LOG"
grep -Fq 'An unreadable data cluster was found.' "$WRITE_LOG"
grep -Fq 'LEVEL_255' "$WRITE_LOG"
payload="$(mcopy -i "$TARGET" ::CONTROL.TXT - 2>/dev/null | tr -d '\r\n')"
[[ "$payload" == 'persistent I/O fault control payload' ]]
cmp -s "$TARGET" "$PRISTINE"

echo '  PASS: ScanDisk sustained-read abort and exhausted-write refusal contracts'
