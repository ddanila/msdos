#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/msd-test.img"
LOG="$OUT/msd-test.log"
PRINT_OUT="$OUT/msd-printer.txt"
EXIT_COM="$OUT/msd-qexit.com"
INTERACTIVE_IMAGE="$OUT/msd-interactive.img"
SERIAL_BASE="$OUT/msd-interactive-serial"
SERIAL_IN="$SERIAL_BASE.in"
SERIAL_OUT="$SERIAL_BASE.out"
INTERACTIVE_LOG="$OUT/msd-interactive.log"

cp "$BASE" "$IMAGE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$IMAGE" "$ROOT/src/CMD/MSD/MSD.EXE" ::MSD.EXE
mcopy -o -i "$IMAGE" "$EXIT_COM" ::QEXIT.COM
printf 'DEVICE=A:\\RAMDRIVE.SYS 64\r\n' | \
    mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'MSD /?\r\n'
    printf 'MSD /B /S /F A:\\MSDRPT.TXT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO MSD_FILE_FAIL\r\n'
    printf 'TYPE A:\\MSDRPT.TXT\r\n'
    printf 'MSD /F /S\r\n'
    printf 'IF EXIST A:\\MSD.TXT ECHO MSD_DEFAULT_FILE\r\n'
    printf 'MSD /I /S /F A:\\MSDI.TXT\r\n'
    printf 'TYPE A:\\MSDI.TXT\r\n'
    printf 'MD A:\\MSDMAP\r\n'
    printf 'SUBST D: A:\\MSDMAP\r\n'
    printf 'MSD /S /F A:\\MSDMAP.TXT\r\n'
    printf 'TYPE A:\\MSDMAP.TXT\r\n'
    printf 'MSD /S /P\r\n'
    printf 'MSD /NOPE\r\n'
    printf 'IF ERRORLEVEL 1 ECHO MSD_BAD_SWITCH_LEVEL1\r\n'
    printf 'ECHO MSD_TEST_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

rm -f "$LOG" "$PRINT_OUT"
timeout 25 qemu-system-i386 \
    -display none -monitor none -boot a -m 4 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -serial stdio -parallel "file:$PRINT_OUT" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 2>/dev/null | tee "$LOG" || true

for marker in \
    'Microsoft Diagnostics-compatible report' \
    'Operating System' 'Computer' 'Memory' 'Video' 'Disk Drives' \
    'IRQ Vectors' 'Device Drivers' 'Network' \
    'Reported DOS version: 6.22' 'True DOS version:     6.22' \
    'B:  logical alias of A: (one physical floppy)' \
    'C:  total      62464 bytes  512-byte sectors  FAT12' \
    'D:  substituted path A:\MSDMAP' \
    'MSD [/B] [/I] [/F [filename]] [/P] [/S]' 'MSD_DEFAULT_FILE' \
    'Extended probing:      Skipped (/I)' \
    'MSD_BAD_SWITCH_LEVEL1' 'MSD_TEST_DONE'; do
    grep -Fq "$marker" "$LOG" || {
        echo "FAIL: missing MSD evidence: $marker" >&2
        sed -n '1,240p' "$LOG" >&2
        exit 1
    }
done

grep -Fq 'Microsoft Diagnostics-compatible report' "$PRINT_OUT" || {
    echo 'FAIL: MSD /P did not emit a printer report' >&2
    exit 1
}

cp "$BASE" "$INTERACTIVE_IMAGE"
mcopy -o -i "$INTERACTIVE_IMAGE" "$ROOT/src/CMD/MSD/MSD.EXE" ::MSD.EXE
mcopy -o -i "$INTERACTIVE_IMAGE" "$EXIT_COM" ::QEXIT.COM
printf '@ECHO OFF\r\nCTTY AUX\r\nMSD\r\nECHO MSD_INTERACTIVE_RETURNED\r\nQEXIT.COM\r\n' | \
    mcopy -o -i "$INTERACTIVE_IMAGE" - ::AUTOEXEC.BAT
rm -f "$SERIAL_IN" "$SERIAL_OUT" "$INTERACTIVE_LOG"
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"
timeout 25 qemu-system-i386 -display none -boot a -m 4 \
    -drive if=floppy,index=0,format=raw,file="$INTERACTIVE_IMAGE",cache=writethrough \
    -serial pipe:"$SERIAL_BASE" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 2>/dev/null &
QEMU_PID=$!
python3 "$ROOT/tests/serial_expect.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$INTERACTIVE_LOG" \
    'Selection:' 'm' 'Selection:' 'x'
wait "$QEMU_PID" || true
exec 3>&-
grep -Fq 'Largest free block:' "$INTERACTIVE_LOG"
grep -Fq 'MSD_INTERACTIVE_RETURNED' "$INTERACTIVE_LOG"

echo '  PASS: MSD summary, file, printer, /I, interactive, and error paths'
