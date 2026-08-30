#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

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

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
exit_com="$OUT/qemu-exit.com"
nasm -f bin "$REPO_ROOT/tests/qemu_exit_probe.asm" -o "$exit_com"
for case_spec in 'ON|ON|EMM386 Active\.' \
    'OFF|OFF|EMM386 Inactive\.' \
    'AUTO|AUTO|EMM386 in Auto mode\.' \
    'WON|W=ON|EMM386 Active\.' \
    'WOFF|W=OFF|EMM386 Active\.'; do
    IFS='|' read -r case_name options expected <<<"$case_spec"
    boot_img="$OUT/floppy-emm386-load-${case_name}.img"
    serial_log="$OUT/emm386-load-${case_name}.log"
    cp "$FLOPPY" "$boot_img"
    mcopy -o -i "$boot_img" "$exit_com" ::QEXIT.COM
    printf 'DEVICE=A:\\EMM386.EXE %s\r\n' "$options" \
        | mcopy -o -i "$boot_img" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'EMM386\r\n'
        printf 'ECHO EMM386_LOAD_OPTION_PASS\r\n'
        printf 'QEXIT.COM\r\n'
    } | mcopy -o -i "$boot_img" - ::AUTOEXEC.BAT

    timeout 35 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 4 \
        -drive if=floppy,index=0,format=raw,file="$boot_img",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >"$serial_log" 2>&1 || true
    if ! grep -Eq "$expected" "$serial_log" \
        || ! grep -q 'EMM386_LOAD_OPTION_PASS' "$serial_log"; then
        echo "FAIL: EMM386 driver-load option $options" >&2
        sed -n '1,120p' "$serial_log"
        exit 1
    fi
done

echo "EMM386 driver-load ON/OFF/AUTO and W= options passed"
