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

handle_com="$OUT/emm386-handle.com"
boot_img="$OUT/floppy-emm386-handle.img"
serial_log="$OUT/emm386-handle.log"
nasm -f bin "$REPO_ROOT/tests/emm386_handle_probe.asm" -o "$handle_com"
cp "$FLOPPY" "$boot_img"
mcopy -o -i "$boot_img" "$handle_com" ::HANDLE.COM
printf 'DEVICE=A:\\EMM386.EXE H=2\r\n' | mcopy -o -i "$boot_img" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'HANDLE.COM\r\n'
} | mcopy -o -i "$boot_img" - ::AUTOEXEC.BAT
timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$boot_img",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$serial_log" 2>&1 || true
if ! grep -q 'EMM386_HANDLE_LIMIT_PASS' "$serial_log"; then
    echo "FAIL: EMM386 H= handle limit" >&2
    sed -n '1,120p' "$serial_log"
    exit 1
fi

echo "EMM386 H= handle limit passed"

for case_spec in 'LVALID|256 L=2000|installed' \
    'LRESERVE|1024 L=3500|rejected' \
    'DVALID|512 D=256|installed' \
    'DRESERVE|128 D=256|rejected'; do
    IFS='|' read -r case_name options expectation <<<"$case_spec"
    probe_com="$OUT/emm386-install-${case_name}.com"
    boot_img="$OUT/floppy-emm386-install-${case_name}.img"
    serial_log="$OUT/emm386-install-${case_name}.log"
    nasm_args=(-f bin)
    if [[ "$expectation" == installed ]]; then
        nasm_args+=(-DEXPECT_INSTALLED)
    fi
    nasm "${nasm_args[@]}" "$REPO_ROOT/tests/emm386_install_probe.asm" \
        -o "$probe_com"
    cp "$FLOPPY" "$boot_img"
    mcopy -o -i "$boot_img" "$probe_com" ::INSTALL.COM
    {
        printf 'DEVICE=A:\\HIMEM.SYS\r\n'
        printf 'DEVICE=A:\\EMM386.EXE %s\r\n' "$options"
    } | mcopy -o -i "$boot_img" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'INSTALL.COM\r\n'
    } | mcopy -o -i "$boot_img" - ::AUTOEXEC.BAT
    timeout 35 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 4 \
        -drive if=floppy,index=0,format=raw,file="$boot_img",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >"$serial_log" 2>&1 || true
    if ! grep -q 'EMM386_INSTALL_EXPECTATION_PASS' "$serial_log"; then
        echo "FAIL: EMM386 $options was not $expectation" >&2
        sed -n '1,120p' "$serial_log"
        exit 1
    fi
done

echo "EMM386 L= XMS and D= DMA reservations passed"

altreg_com="$OUT/emm386-altreg.com"
boot_img="$OUT/floppy-emm386-altreg.img"
serial_log="$OUT/emm386-altreg.log"
nasm -f bin "$REPO_ROOT/tests/emm386_altreg_probe.asm" -o "$altreg_com"
cp "$FLOPPY" "$boot_img"
mcopy -o -i "$boot_img" "$altreg_com" ::ALTREG.COM
printf 'DEVICE=A:\\EMM386.EXE A=2\r\n' | mcopy -o -i "$boot_img" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'ALTREG.COM\r\n'
} | mcopy -o -i "$boot_img" - ::AUTOEXEC.BAT
timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$boot_img",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$serial_log" 2>&1 || true
if ! grep -q 'EMM386_ALTREG_LIMIT_PASS' "$serial_log"; then
    echo "FAIL: EMM386 A= alternate-register limit" >&2
    sed -n '1,120p' "$serial_log"
    exit 1
fi

echo "EMM386 A= alternate-register limit passed"
