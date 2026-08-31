#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/msd-test.img"
LOG="$OUT/msd-test.log"
EXIT_COM="$OUT/msd-qexit.com"
INTERACTIVE_IMAGE="$OUT/msd-interactive.img"
SERIAL_BASE="$OUT/msd-interactive-serial"
SERIAL_IN="$SERIAL_BASE.in"
SERIAL_OUT="$SERIAL_BASE.out"
INTERACTIVE_LOG="$OUT/msd-interactive.log"
MANAGER_IMAGE="$OUT/msd-manager.img"
MANAGER_LOG="$OUT/msd-manager.log"

cp "$BASE" "$IMAGE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
mcopy -o -i "$IMAGE" "$ROOT/src/CMD/MSD/MSD.EXE" ::MSD.EXE
mcopy -o -i "$IMAGE" "$EXIT_COM" ::QEXIT.COM
printf 'Ada Lovelace\r\nAnalytical Engines\r\n' | \
    mcopy -o -i "$IMAGE" - ::MSDINFO.TXT
printf 'DEVICE=A:\\RAMDRIVE.SYS 64\r\n' | \
    mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'MSD /?\r\n'
    printf 'MSD /B /S A:\\MSDRPT.TXT\r\n'
    printf 'IF ERRORLEVEL 1 ECHO MSD_FILE_FAIL\r\n'
    printf 'TYPE A:\\MSDRPT.TXT\r\n'
    printf 'MSD /I /P A:\\MSDI.TXT\r\n'
    printf 'TYPE A:\\MSDI.TXT\r\n'
    printf 'MSD /F A:\\MSDF.TXT < A:\\MSDINFO.TXT\r\n'
    printf 'TYPE A:\\MSDF.TXT\r\n'
    printf 'MD A:\\MSDMAP\r\n'
    printf 'SUBST D: A:\\MSDMAP\r\n'
    printf 'MSD /P A:\\MSDMAP.TXT\r\n'
    printf 'TYPE A:\\MSDMAP.TXT\r\n'
    printf 'MSD /S\r\n'
    printf 'MSD /NOPE\r\n'
    printf 'IF ERRORLEVEL 1 ECHO MSD_BAD_SWITCH_LEVEL1\r\n'
    printf 'ECHO MSD_TEST_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

rm -f "$LOG"
timeout 35 qemu-system-i386 \
    -display none -monitor none -boot a -m 4 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 2>/dev/null | tee "$LOG" || true

for marker in \
    'Computer: IBM PC/AT compatible' \
    'Mouse: Not detected' 'Other Adapters: None detected' \
    'Disk Drives: 1 floppy drive(s)' 'LPT Ports: 1' 'COM Ports: 1' \
    'Windows Information: Not Detected' \
    'Operating System' 'Computer' 'ROM Inventory' 'Memory' 'Video' 'Disk Drives' \
    'COM and LPT Ports' 'Input Devices' 'DOS Configuration' 'IRQ Vectors' 'Resident Programs' 'Device Drivers' 'Network' 'Windows Information' \
    'Reported DOS version: 6.22' 'True DOS version:     6.22' 'DOS OEM/serial:' \
    'Internal revision:' 'DOS memory location:' 'Boot drive:            A:' \
    'Current drive:         A:' 'Path to program:' 'Environment strings:' 'COMSPEC=' \
    'Processor:             486-class x86' \
    'BIOS machine ID:' 'BIOS date:' 'BIOS base memory:' 'Bus type:              ISA/AT compatible' 'DMA controller:        Present' \
    'Cascaded IRQ2:         Yes' 'BIOS data segment:' \
    'Extended memory:' \
    'Startup display:' 'Game adapter:' 'COM1 base address:     03F8h' \
    'BIOS ROM range:' 'BIOS ROM checksum:' 'Option ROM ' 'Option ROM scan:       Skipped (/I)' \
    'COM1 BIOS status:' 'COM1 UART:' 'COM1 current rate:' 'LPT1 BIOS status:' \
    'COM1 parity:           None' 'COM1 data bits:        8' 'COM1 stop bits:        1' \
    'COM1 carrier detect:   Yes' 'COM1 ring indicator:   No' \
    'COM1 data set ready:   Yes' 'COM1 clear to send:    Yes' \
    'LPT1 on line:          Yes' 'LPT1 paper out:        No' \
    'LPT1 I/O error:        No' 'LPT1 timeout:          No' \
    'LPT1 busy:             No' 'LPT1 acknowledge:      No' \
    'Port status probing:   Skipped (/I)' 'UART detection:        Skipped (/I)' \
    'Text rows:' 'Character height:' 'Active adapter:        VGA color' \
    'Alternate adapter:' 'VESA support:          Installed' 'VESA version:' \
    'VESA OEM name:' 'VESA probing:          Skipped (/I)' \
    'Keyboard shift flags:' 'Mouse driver:          Not probed (/I)' \
    'Allocation strategy:' 'UMB chain linked:' 'Write verification:' \
    'Extended BREAK check:' 'Code pages:' 'Country code:' 'Date format:' 'Environment:' \
    'B:  logical alias of A: (one physical floppy)' \
    'A:  physical geometry 80 cylinders, 2 heads, 512 bytes/sector, 36 sectors/track' \
    'C:  total      62464 bytes  512-byte sectors  FAT12' \
    'LASTDRIVE=E:' \
    'D:  substituted path A:\MSDMAP' \
    'owner=0000' 'Windows installation:  Not detected' \
    'MSD [/I] [/F[drive:][path]filename] [/P[drive:][path]filename]' \
    'Extended probing:      Skipped (/I)' \
    'Name: Ada Lovelace' 'Company: Analytical Engines' \
    'MSD_BAD_SWITCH_LEVEL1' 'MSD_TEST_DONE'; do
    grep -Fq "$marker" "$LOG" || {
        echo "FAIL: missing MSD evidence: $marker" >&2
        sed -n '1,240p' "$LOG" >&2
        exit 1
    }
done

cp "$BASE" "$MANAGER_IMAGE"
mcopy -o -i "$MANAGER_IMAGE" "$ROOT/src/CMD/MSD/MSD.EXE" ::MSD.EXE
mcopy -o -i "$MANAGER_IMAGE" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
mcopy -o -i "$MANAGER_IMAGE" "$ROOT/src/MEMM/MEMM/EMM386.EXE" ::EMM386.EXE
mcopy -o -i "$MANAGER_IMAGE" "$EXIT_COM" ::QEXIT.COM
printf 'DEVICE=A:\\HIMEM.SYS\r\nDEVICE=A:\\EMM386.EXE RAM M5\r\n' | \
    mcopy -o -i "$MANAGER_IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nCTTY AUX\r\nMSD /P A:\\MSDMEM.TXT\r\nTYPE A:\\MSDMEM.TXT\r\nQEXIT.COM\r\n' | \
    mcopy -o -i "$MANAGER_IMAGE" - ::AUTOEXEC.BAT
rm -f "$MANAGER_LOG"
timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -boot a -m 16 \
    -drive if=floppy,index=0,format=raw,file="$MANAGER_IMAGE",cache=writethrough \
    -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 2>/dev/null \
    >"$MANAGER_LOG" || true
for marker in \
    'XMS manager:           Installed' 'XMS version:' 'XMS driver version:' \
    'HMA available:' 'A20 line:' \
    'Largest free XMS:' 'Total free XMS:' \
    'EMS manager:           Installed' 'EMS version:' 'EMS page frame:' \
    'Free EMS pages:' 'Total EMS pages:'; do
    grep -Fq "$marker" "$MANAGER_LOG" || {
        echo "FAIL: missing MSD memory-manager evidence: $marker" >&2
        sed -n '1,180p' "$MANAGER_LOG" >&2
        exit 1
    }
done

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
    'Selection:' 'm' 'Selection:' 'p' 'Selection:' 'k' 'Selection:' 'g' 'Selection:' 't' 'Selection:' 'w' 'Selection:' 'x'
wait "$QEMU_PID" || true
exec 3>&-
grep -Fq 'Largest free block:' "$INTERACTIVE_LOG"
grep -Fq 'COM1 base address:' "$INTERACTIVE_LOG"
grep -Fq 'Keyboard shift flags:' "$INTERACTIVE_LOG"
grep -Fq 'Allocation strategy:' "$INTERACTIVE_LOG"
grep -Fq 'Resident Programs' "$INTERACTIVE_LOG"
grep -Fq 'Windows installation:' "$INTERACTIVE_LOG"
grep -Fq 'MSD_INTERACTIVE_RETURNED' "$INTERACTIVE_LOG"

echo '  PASS: MSD retail syntax, summary, report file, /I, interactive, and error paths'
