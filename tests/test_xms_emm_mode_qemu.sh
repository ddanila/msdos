#!/bin/bash
# Public XMS lifetime across our private EMM mode control; no vendor code.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="${FLOPPY_IMAGE:-$ROOT/out/floppy.img}"
for tool in nasm mcopy qemu-system-i386 timeout shasum rg; do
    command -v "$tool" >/dev/null
done
test -f "$INPUT"
RUN=$(mktemp -d "$ROOT/out/xms-emm-mode.XXXXXX")
echo "Evidence: $RUN"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
shasum -a 256 "$INPUT" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" \
    "$ROOT/src/MEMM/MEMM/EMM386.EXE" > "$RUN/inputs.sha256"
qemu-system-i386 --version > "$RUN/emulator.txt"
for variant in good wrong-address wrong-data wrong-descriptor; do
    args=(-f bin)
    if [[ "$variant" == wrong-address ]]; then args+=(-DWRONG_ADDRESS); fi
    if [[ "$variant" == wrong-data ]]; then args+=(-DWRONG_DATA); fi
    if [[ "$variant" == wrong-descriptor ]]; then args+=(-DWRONG_DESCRIPTOR); fi
    for residency in LOW HIGH; do
        prefix="$RUN/$variant-$residency"
        hma=0
        if [[ "$residency" == HIGH ]]; then hma=1; fi
        nasm "${args[@]}" -DEXPECT_HMA="$hma" "$ROOT/tests/xms_emm_mode_probe.asm" -o "$prefix.com"
        cp "$INPUT" "$prefix.img"
        mcopy -o -i "$prefix.img" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
        mcopy -o -i "$prefix.img" "$ROOT/src/MEMM/MEMM/EMM386.EXE" ::EMM386.EXE
        mcopy -o -i "$prefix.img" "$prefix.com" ::XMSMODE.COM
        printf 'DEVICE=A:\\HIMEM.SYS\r\nDOS=%s\r\nDEVICE=A:\\EMM386.EXE M5\r\n' "$residency" \
            | mcopy -o -i "$prefix.img" - ::CONFIG.SYS
        printf '@ECHO OFF\r\nCTTY AUX\r\nXMSMODE.COM\r\n' \
            | mcopy -o -i "$prefix.img" - ::AUTOEXEC.BAT
        result=0
        timeout 35 qemu-system-i386 -display none -monitor none \
            -machine pc -cpu 486 -m 8 -boot a -serial stdio -no-reboot \
            -drive "if=floppy,index=0,format=raw,file=$prefix.img" \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$prefix.log" 2>&1 || result=$?
        if [[ "$variant" == good ]]; then
            [[ "$result" == 33 ]]
            rg -q '^XMS_EMM_MODE_PASS' "$prefix.log"
            ! rg -q 'XMS_EMM_MODE_FAIL' "$prefix.log"
        else
            [[ "$result" == 35 ]]
            rg -q '^XMS_EMM_MODE_FAIL' "$prefix.log"
            ! rg -q 'XMS_EMM_MODE_PASS' "$prefix.log"
        fi
        echo "PASS: $variant DOS=$residency"
    done
done
echo "XMS owner survives EMM modes; address/data/descriptor controls rejected. Evidence: $RUN"
