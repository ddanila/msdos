#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
PROBE="$OUT/config-numlock-probe.com"
EXIT_COM="$OUT/config-numlock-qexit.com"

nasm -f bin "$ROOT/tests/config_numlock_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"

for state in ON OFF; do
    image="$OUT/config-numlock-$state.img"
    serial="$OUT/config-numlock-$state.log"
    cp "$BASE" "$image"
    printf 'NUMLOCK=%s\r\n' "$state" | mcopy -o -i "$image" - ::CONFIG.SYS
    printf '@ECHO OFF\r\nCTTY AUX\r\nNLPROBE.COM\r\nQEXIT.COM\r\n' | \
        mcopy -o -i "$image" - ::AUTOEXEC.BAT
    mcopy -o -i "$image" "$PROBE" ::NLPROBE.COM
    mcopy -o -i "$image" "$EXIT_COM" ::QEXIT.COM
    set +e
    timeout 30 qemu-system-i386 -display none \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -m 4 -serial stdio \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        2>/dev/null | tee "$serial" >/dev/null
    set -e
    grep -Fq "NUMLOCK=$state" "$serial"
done
echo '  PASS: CONFIG.SYS NUMLOCK=ON and OFF set the BIOS toggle state'
