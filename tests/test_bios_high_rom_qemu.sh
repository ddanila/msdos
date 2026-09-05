#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
for tool in nasm mcopy qemu-system-i386 timeout rg; do
    command -v "$tool" >/dev/null
done
test -f "$ROOT/out/floppy.img"
scratch=$(mktemp -d "$ROOT/out/bios-high-rom.XXXXXX")
# Keep failed probes recoverable under out/, including image and serial log.
"$ROOT/bin/jwasm-masm" "-I$ROOT/src/BIOS" \
    "$ROOT/tests/bios_high_rom_gate_masm.asm,$scratch/gate.obj;"
for mode in LOW HIGH VECTOR_LOW VECTOR_HIGH IRET_LOW IRET_HIGH TIMER_LOW TIMER_HIGH FRAME_LOW FRAME_HIGH FRAME_IRET_LOW FRAME_IRET_HIGH TAIL_LOW TAIL_HIGH TAIL_IRET_LOW TAIL_IRET_HIGH; do
    options=(-DEXPECT_LOW)
    dos_mode=LOW
    if [[ "$mode" == *HIGH ]]; then
        options+=(-DEXPECT_HIGH)
        dos_mode=HIGH
    fi
    if [[ "$mode" == VECTOR_* || "$mode" == IRET_* ]]; then options+=(-DUSE_SAVED_VECTOR); fi
    if [[ "$mode" == IRET_* ]]; then options+=(-DVECTOR_IRET); fi
    if [[ "$mode" == TIMER_* ]]; then options+=(-DTEST_TIMER); fi
    if [[ "$mode" == FRAME_* ]]; then options+=(-DUSE_SUPPLIED_FLAGS); fi
    if [[ "$mode" == FRAME_IRET_* ]]; then options+=(-DVECTOR_IRET); fi
    if [[ "$mode" == TAIL_* ]]; then options+=(-DUSE_SUPPLIED_FLAGS -DUSE_TAIL); fi
    if [[ "$mode" == TAIL_IRET_* ]]; then options+=(-DVECTOR_IRET); fi
    nasm -f bin -I"$ROOT/src/BIOS/" "${options[@]}" \
        "$ROOT/tests/bios_high_rom_probe.asm" -o "$scratch/probe.com"
    cp "$ROOT/out/floppy.img" "$scratch/$mode.img"
    mcopy -o -i "$scratch/$mode.img" "$scratch/probe.com" ::BIOROM.COM
    printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\nDOS=%s\r\n' "$dos_mode" \
        | mcopy -o -i "$scratch/$mode.img" - ::CONFIG.SYS
    printf '@ECHO OFF\r\nCTTY AUX\r\nBIOROM.COM\r\n' \
        | mcopy -o -i "$scratch/$mode.img" - ::AUTOEXEC.BAT
    timeout 35 qemu-system-i386 -display none -monitor none \
        -machine pc -cpu 486 -m 8 -boot a -no-reboot -serial stdio \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "if=floppy,index=0,format=raw,file=$scratch/$mode.img,cache=writethrough" \
        > "$scratch/$mode.log" 2>&1 || true
    if ! rg -q 'BIOS_HIGH_ROM_PASS' "$scratch/$mode.log"; then
        echo "FAIL: $mode BIOS ROM-return boundary; evidence: $scratch"
        sed -n '1,120p' "$scratch/$mode.log"
        exit 1
    fi
    echo "PASS: $mode BIOS ROM-return boundary ($scratch/$mode.log)"
done
nasm -f bin -I"$ROOT/src/BIOS/" -DEXPECT_HIGH -DOMIT_A20_RESTORE \
    "$ROOT/tests/bios_high_rom_probe.asm" -o "$scratch/broken.com"
cp "$scratch/HIGH.img" "$scratch/BROKEN.img"
mcopy -o -i "$scratch/BROKEN.img" "$scratch/broken.com" ::BIOROM.COM
timeout 15 qemu-system-i386 -display none -monitor none \
    -machine pc -cpu 486 -m 8 -boot a -no-reboot -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -drive "if=floppy,index=0,format=raw,file=$scratch/BROKEN.img,cache=writethrough" \
    > "$scratch/BROKEN.log" 2>&1 || true
if ! rg -q 'BIOS_HIGH_ROM_BEGIN' "$scratch/BROKEN.log" \
    || rg -q 'BIOS_HIGH_ROM_PASS' "$scratch/BROKEN.log"; then
    echo "FAIL: missing-A20-restore control was not rejected after probe startup: $scratch"
    exit 1
fi
echo "PASS: missing-A20-restore negative control rejected ($scratch/BROKEN.log)"
