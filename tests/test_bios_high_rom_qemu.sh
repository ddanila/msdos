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
for mode in LOW HIGH; do
    options=(-DEXPECT_LOW)
    if [[ "$mode" == HIGH ]]; then options+=(-DEXPECT_HIGH); fi
    nasm -f bin -I"$ROOT/src/BIOS/" "${options[@]}" \
        "$ROOT/tests/bios_high_rom_probe.asm" -o "$scratch/probe.com"
    cp "$ROOT/out/floppy.img" "$scratch/$mode.img"
    mcopy -o -i "$scratch/$mode.img" "$scratch/probe.com" ::BIOROM.COM
    printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\nDOS=%s\r\n' "$mode" \
        | mcopy -o -i "$scratch/$mode.img" - ::CONFIG.SYS
    printf '@ECHO OFF\r\nCTTY AUX\r\nBIOROM.COM\r\n' \
        | mcopy -o -i "$scratch/$mode.img" - ::AUTOEXEC.BAT
    timeout 35 qemu-system-i386 -display none -monitor none \
        -machine pc -cpu 486 -m 8 -boot a -no-reboot -serial stdio \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "if=floppy,index=0,format=raw,file=$scratch/$mode.img,cache=writethrough" \
        > "$scratch/$mode.log" 2>&1 || true
    if ! rg -q 'BIOS_HIGH_ROM_PASS' "$scratch/$mode.log"; then
        echo "FAIL: DOS=$mode BIOS ROM-return boundary; evidence: $scratch"
        sed -n '1,120p' "$scratch/$mode.log"
        exit 1
    fi
    echo "PASS: DOS=$mode BIOS ROM-return boundary ($scratch/$mode.log)"
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
