#!/bin/bash
set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
SOURCE="$OUT/setup-floppy-source.img"
TARGET="$OUT/setup-floppy-target.img"
LOG="$OUT/setup-floppy.log"
BOOT_LOG="$OUT/setup-floppy-boot.log"

[[ -f "$OUT/distribution/disk1.img" ]] || {
    echo "missing distribution disk 1; run make distribution" >&2
    exit 1
}
cp "$OUT/distribution/disk1.img" "$SOURCE"
mformat -C -i "$TARGET" -f 1440 ::
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$OUT/setup-floppy-qexit.com"
mcopy -o -i "$SOURCE" "$OUT/setup-floppy-qexit.com" ::QEXIT.COM
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'SETUP B:\\DOS /F /B /Y\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SETUP_FLOPPY_FAILED\r\n'
    printf 'SETUP /E\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SETUP_WINDOWS_EXCLUDED\r\n'
    printf 'ECHO SETUP_FLOPPY_DONE\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$SOURCE" - ::AUTOEXEC.BAT

timeout 45 qemu-system-i386 -display none -monitor none -m 4 \
    -drive if=floppy,index=0,format=raw,file="$SOURCE",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET",cache=writethrough \
    -boot a -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$LOG" 2>&1 || true

grep -Fq 'Minimal startup-disk installation to B:\DOS' "$LOG"
grep -q 'Setup completed successfully' "$LOG"
! grep -q SETUP_FLOPPY_FAILED "$LOG"
grep -q 'Windows companion programs' "$LOG"
grep -q SETUP_WINDOWS_EXCLUDED "$LOG"
grep -q SETUP_FLOPPY_DONE "$LOG"
for path in IO.SYS MSDOS.SYS COMMAND.COM DOS/COMMAND.COM DOS/SYS.COM \
            DOS/FORMAT.COM DOS/FDISK.EXE DOS/SETUP.EXE CONFIG.SYS AUTOEXEC.BAT; do
    mdir -a -i "$TARGET" "::$path" >/dev/null
done
! mdir -i "$TARGET" ::DOS/EMM386.EXE >/dev/null 2>&1
config="$(mtype -i "$TARGET" ::CONFIG.SYS | tr -d '\r')"
autoexec="$(mtype -i "$TARGET" ::AUTOEXEC.BAT | tr -d '\r')"
grep -q 'FILES=20' <<<"$config"
grep -q 'BUFFERS=10' <<<"$config"
grep -Fq 'PATH B:\DOS' <<<"$autoexec"

printf '@ECHO OFF\r\nCTTY AUX\r\nECHO SETUP_RECOVERY_BOOTED\r\n' |
    mcopy -o -i "$TARGET" - ::AUTOEXEC.BAT
timeout 20 qemu-system-i386 -display none -monitor none -m 4 \
    -drive if=floppy,index=0,format=raw,file="$TARGET",cache=writethrough \
    -boot a -serial stdio -no-reboot </dev/null >"$BOOT_LOG" 2>&1 || true
grep -q SETUP_RECOVERY_BOOTED "$BOOT_LOG"

echo "SETUP /F bootable recovery disk and explicit /E exclusion contracts passed"
