#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE=${FLOPPY_IMAGE:-$OUT/floppy.img}

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done
[[ -f "$BASE" ]] || {
    echo "ERROR: $BASE not found; run 'make deploy' first" >&2
    exit 1
}

exit_com="$OUT/qemu-exit.com"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$exit_com"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

for handles in {24..32}; do
    image="$OUT/floppy-emm386-phase-$handles.img"
    log="$OUT/emm386-phase-$handles.log"
    marker="EMM386_PHASE_${handles}_PASS"
    cp "$BASE" "$image"
    mcopy -o -i "$image" "$exit_com" ::QEXIT.COM
    {
        printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF /NUMHANDLES=%s\r\n' "$handles"
        printf 'DEVICE=A:\\EMM386.EXE RAM M5\r\n'
        printf 'DOS=HIGH,UMB\r\n'
    } | mcopy -o -i "$image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'ECHO %s\r\n' "$marker"
        printf 'QEXIT.COM\r\n'
    } | mcopy -o -i "$image" - ::AUTOEXEC.BAT

    timeout 25 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 8 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$log" 2>&1 || true
    if ! grep -Fq "$marker" "$log"; then
        echo "FAIL: EMM386 did not boot at HIMEM /NUMHANDLES=$handles" >&2
        sed -n '1,120p' "$log" >&2
        exit 1
    fi
done

echo '  PASS: EMM386 boots across HIMEM /NUMHANDLES=24..32 address phases'
