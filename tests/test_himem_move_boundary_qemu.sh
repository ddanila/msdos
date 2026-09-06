#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null || { echo "Missing $tool"; exit 1; }
done
[[ -f "$BASE" ]] || { echo 'Build a boot floppy first'; exit 1; }
nasm -f bin "$ROOT/tests/himem_move_boundary_probe.asm" -o "$OUT/himem-move-boundary.com"
for mode in LOW HIGH; do
    image="$OUT/himem-move-boundary-$mode.img"
    log="$OUT/himem-move-boundary-$mode.log"
    cp "$BASE" "$image"
    mcopy -o -i "$image" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
    mcopy -o -i "$image" "$OUT/himem-move-boundary.com" ::BOUNDARY.COM
    printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\nDOS=%s\r\n' "$mode" | mcopy -o -i "$image" - ::CONFIG.SYS
    printf '@ECHO OFF\r\nCTTY AUX\r\nBOUNDARY.COM\r\n' | mcopy -o -i "$image" - ::AUTOEXEC.BAT
    timeout 25 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive "if=floppy,format=raw,file=$image" -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$log" 2>&1 || true
    if ! grep -Fq HIMEM_MOVE_BOUNDARY_PASS "$log" || grep -Fq HIMEM_MOVE_BOUNDARY_FAIL "$log"; then
        cat "$log"
        exit 1
    fi
    echo "PASS: XMS moves crossing 64 KiB with DOS=$mode"
done
