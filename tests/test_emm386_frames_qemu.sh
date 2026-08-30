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
for case_spec in 'M1 M1 0xc000' 'M5 M5 0xd000' 'M9 M9 0xe000' \
    'FRAME FRAME=D000 0xd000' 'SLASHP /PD000 0xd000'; do
    read -r case_name option expected <<<"$case_spec"
    boot_img="$OUT/floppy-emm386-frame-${case_name}.img"
    probe_com="$OUT/emm386-frame-${case_name}.com"
    serial_log="$OUT/emm386-frame-${case_name}.log"
    cp "$FLOPPY" "$boot_img"
    nasm -f bin -DEXPECT_FRAME="$expected" \
        "$REPO_ROOT/tests/emm386_frame_probe.asm" -o "$probe_com"
    mcopy -o -i "$boot_img" "$probe_com" ::FRAME.COM
    printf 'DEVICE=A:\\EMM386.EXE %s\r\n' "$option" \
        | mcopy -o -i "$boot_img" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'FRAME.COM\r\n'
    } | mcopy -o -i "$boot_img" - ::AUTOEXEC.BAT

    timeout 35 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 4 \
        -drive if=floppy,index=0,format=raw,file="$boot_img",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >"$serial_log" 2>&1 || true
    if ! grep -q 'EMM386_FRAME_PASS' "$serial_log"; then
        echo "FAIL: EMM386 $option did not expose page frame $expected" >&2
        sed -n '1,120p' "$serial_log"
        exit 1
    fi
done

echo "EMM386 M1-M9, FRAME=, and /P page-frame selectors passed"

for case_spec in 'DEFAULT B=4000 default' 'LOW B=1000 low'; do
    read -r case_name option expectation <<<"$case_spec"
    boot_img="$OUT/floppy-emm386-banking-${case_name}.img"
    probe_com="$OUT/emm386-banking-${case_name}.com"
    serial_log="$OUT/emm386-banking-${case_name}.log"
    nasm_args=(-f bin)
    if [[ "$expectation" == low ]]; then
        nasm_args+=(-DEXPECT_LOW)
    fi
    nasm "${nasm_args[@]}" "$REPO_ROOT/tests/emm386_banking_probe.asm" \
        -o "$probe_com"
    cp "$FLOPPY" "$boot_img"
    mcopy -o -i "$boot_img" "$probe_com" ::BANKING.COM
    printf 'DEVICE=A:\\EMM386.EXE %s\r\n' "$option" \
        | mcopy -o -i "$boot_img" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'BANKING.COM\r\n'
    } | mcopy -o -i "$boot_img" - ::AUTOEXEC.BAT
    timeout 35 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 4 \
        -drive if=floppy,index=0,format=raw,file="$boot_img",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >"$serial_log" 2>&1 || true
    if ! grep -q 'EMM386_BANKING_BASE_PASS' "$serial_log"; then
        echo "FAIL: EMM386 $option banking boundary" >&2
        sed -n '1,120p' "$serial_log"
        exit 1
    fi
done

echo "EMM386 B= banking boundaries passed"

boot_img="$OUT/floppy-emm386-page-assignment.img"
probe_com="$OUT/emm386-page-assignment.com"
serial_log="$OUT/emm386-page-assignment.log"
nasm -f bin "$REPO_ROOT/tests/emm386_page_assignment_probe.asm" -o "$probe_com"
cp "$FLOPPY" "$boot_img"
mcopy -o -i "$boot_img" "$probe_com" ::PAGE.COM
printf 'DEVICE=A:\\EMM386.EXE P0=D000 P1=D400 P2=D800 P3=DC00 P4=9000 P200=E000\r\n' \
    | mcopy -o -i "$boot_img" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'PAGE.COM\r\n'
} | mcopy -o -i "$boot_img" - ::AUTOEXEC.BAT
timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$boot_img",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$serial_log" 2>&1 || true
if ! grep -q 'EMM386_PAGE_ASSIGNMENT_PASS' "$serial_log"; then
    echo "FAIL: EMM386 Pn= sparse physical-page assignment" >&2
    sed -n '1,120p' "$serial_log"
    exit 1
fi

echo "EMM386 Pn= sparse physical-page assignment passed"
