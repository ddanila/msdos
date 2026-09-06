#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/floppy-emm386-qemu.img"
PROBE_COM="$OUT/emm386-probe.com"
AUTO_PROBE_COM="$OUT/emm386-auto-probe.com"
OFF_PROBE_COM="$OUT/emm386-off-probe.com"
DRIVER_PROBE_COM="$OUT/emm386-driver-request-probe.com"
OWNER_MODE_COM="$OUT/emm386-owner-mode.com"
SERIAL_LOG="$OUT/emm386-qemu.log"

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

for tool in nasm mcopy qemu-system-i386 timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool"
        exit 1
    fi
done

cp "$FLOPPY" "$BOOT_IMG"
nasm -f bin "$REPO_ROOT/tests/emm386_probe.asm" -o "$PROBE_COM"
nasm -DNO_QEMU_EXIT -f bin "$REPO_ROOT/tests/emm386_probe.asm" -o "$AUTO_PROBE_COM"
nasm -DEXPECT_OFF -DNO_QEMU_EXIT -f bin "$REPO_ROOT/tests/emm386_probe.asm" -o "$OFF_PROBE_COM"
nasm -f bin "$REPO_ROOT/tests/emm386_driver_request_probe.asm" -o "$DRIVER_PROBE_COM"
nasm -f bin "$REPO_ROOT/tests/emm386_owner_mode_probe.asm" -o "$OWNER_MODE_COM"

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
mcopy -o -i "$BOOT_IMG" "$PROBE_COM" ::EMMPROBE.COM
mcopy -o -i "$BOOT_IMG" "$AUTO_PROBE_COM" ::AUTOPRB.COM
mcopy -o -i "$BOOT_IMG" "$OFF_PROBE_COM" ::OFFPROBE.COM
mcopy -o -i "$BOOT_IMG" "$DRIVER_PROBE_COM" ::DRVPROBE.COM
mcopy -o -i "$BOOT_IMG" "$OWNER_MODE_COM" ::OWNMODE.COM
printf 'DEVICE=A:\\EMM386.EXE M5\r\n' \
    | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'OWNMODE.COM\r\n'
    printf 'DRVPROBE.COM\r\n'
    printf 'EMM386\r\n'
    printf 'EMM386 OFF\r\n'
    printf 'OFFPROBE.COM\r\n'
    printf 'EMM386\r\n'
    printf 'EMM386 ON\r\n'
    printf 'EMM386\r\n'
    printf 'EMM386 AUTO\r\n'
    printf 'EMM386\r\n'
    printf 'EMM386 ON W=ON\r\n'
    printf 'EMM386 W=OFF\r\n'
    printf 'EMM386 ON OFF\r\n'
    printf 'ECHO EMM386_COMMAND_PASS\r\n'
    printf 'EMM386 AUTO\r\n'
    printf 'AUTOPRB.COM\r\n'
    printf 'ECHO EMM386_AUTO_RELEASE_BEGIN\r\n'
    printf 'EMM386\r\n'
    printf 'ECHO EMM386_AUTO_RELEASE_END\r\n'
    printf 'EMM386 ON\r\n'
    printf 'EMMPROBE.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

timeout 35 qemu-system-i386 \
    -display none \
    -monitor none \
    -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$SERIAL_LOG" 2>&1 || true

if grep -q 'EMM386_OWNER_MODE_PASS' "$SERIAL_LOG" \
    && grep -q 'EMM386_DRIVER_REQUEST_PASS' "$SERIAL_LOG" \
    && grep -q 'EMM386_API_PASS' "$SERIAL_LOG" \
    && grep -q 'EMM386_COMMAND_PASS' "$SERIAL_LOG" \
    && grep -q 'EMM386_OFF_API_PASS' "$SERIAL_LOG" \
    && [[ $(grep -c 'EMM386 Active\.' "$SERIAL_LOG") -eq 5 ]] \
    && [[ $(grep -c 'EMM386 Inactive\.' "$SERIAL_LOG") -eq 6 ]] \
    && [[ $(grep -c 'EMM386 is in Auto mode\.' "$SERIAL_LOG") -eq 4 ]] \
    && [[ $(grep -c 'Weitek Coprocessor not installed' "$SERIAL_LOG") -eq 2 ]] \
    && [[ $(grep -c 'MICROSOFT Expanded Memory Manager 386  Version 4.49' "$SERIAL_LOG") -eq 5 ]] \
    && grep -q 'Available expanded memory pages' "$SERIAL_LOG" \
    && grep -q 'Total handles' "$SERIAL_LOG" \
    && grep -q 'Invalid parameter - OFF' "$SERIAL_LOG" \
    && sed -n '/EMM386_AUTO_RELEASE_BEGIN/,/EMM386_AUTO_RELEASE_END/p' "$SERIAL_LOG" | grep -q 'EMM386 Inactive\.'; then
    echo "  PASS: EMM386 driver API and complete runtime command grammar passed"
    exit 0
fi

echo "  FAIL: EMM386 functional probe did not complete"
sed -n '1,160p' "$SERIAL_LOG"
exit 1
