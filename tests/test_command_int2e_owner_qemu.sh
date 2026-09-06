#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="${FLOPPY_IMAGE:-$ROOT/out/floppy.img}"
test -f "$INPUT"
for tool in nasm mcopy mdel mtype timeout qemu-system-i386 rg shasum; do
    command -v "$tool" >/dev/null
done
RUN=$(mktemp -d "$ROOT/out/command-int2e-owner.XXXXXX")
echo "Evidence: $RUN"
export MTOOLS_SKIP_CHECK=1 MTOOLS_NO_VFAT=1
qemu-system-i386 --version > "$RUN/emulator.txt"
shasum -a 256 "$INPUT" "$ROOT/src/CMD/COMMAND/COMMAND.COM" \
    "$ROOT/src/DEV/HIMEM/HIMEM.SYS" > "$RUN/inputs.sha256"
for variant in good wrong-stack; do
for mode in LOW HIGH; do
    args=(-f bin -DEXPECT_HMA=0)
    if [[ "$mode" == HIGH ]]; then args=(-f bin -DEXPECT_HMA=1); fi
    if [[ "$variant" == wrong-stack ]]; then args+=(-DEXPECT_CALLER_STACK); fi
    prefix="$RUN/$variant-$mode"
    nasm "${args[@]}" "$ROOT/tests/command_int2e_owner_probe.asm" -o "$prefix.com"
    disk="$prefix.img"
    cp "$INPUT" "$disk"
    mcopy -o -i "$disk" "$ROOT/src/CMD/COMMAND/COMMAND.COM" ::COMMAND.COM
    mcopy -o -i "$disk" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
    mcopy -o -i "$disk" "$prefix.com" ::I2EOWNER.COM
    # Remove only our probe outputs from the disposable copy, never the input.
    mdel -i "$disk" ::I2EINT.TXT ::I2EEXT.TXT 2>/dev/null || true
    for output in I2EINT.TXT I2EEXT.TXT; do
        if mtype -i "$disk" "::$output" >/dev/null 2>&1; then
            echo "FAIL: stale probe output $output in private image" >&2
            exit 1
        fi
    done
    printf 'DEVICE=A:\\HIMEM.SYS\r\nDOS=%s\r\nBUFFERS=15\r\n' "$mode" \
        | mcopy -o -i "$disk" - ::CONFIG.SYS
    printf '@ECHO OFF\r\nCTTY AUX\r\nI2EOWNER.COM\r\n' \
        | mcopy -o -i "$disk" - ::AUTOEXEC.BAT
    result=0
    timeout 35 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 8 \
        -drive "if=floppy,index=0,format=raw,file=$disk" -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$prefix.log" 2>&1 || result=$?
    if [[ "$variant" == good ]]; then
        [[ "$result" == 33 ]]
        rg -q 'COMMAND_INT2E_OWNER_PASS' "$prefix.log"
        ! rg -q 'COMMAND_INT2E_OWNER_FAIL' "$prefix.log"
    else
        [[ "$result" == 35 ]]
        rg -q 'COMMAND_INT2E_OWNER_FAIL' "$prefix.log"
        ! rg -q 'COMMAND_INT2E_OWNER_PASS' "$prefix.log"
    fi
    echo "PASS: $variant DOS=$mode"
done
done
