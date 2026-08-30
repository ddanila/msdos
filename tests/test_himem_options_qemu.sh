#!/bin/bash

set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
FLOPPY="$OUT/floppy.img"
IMAGE="$OUT/floppy-himem-options.img"
LOG="$OUT/himem-options.log"
PROBE="$OUT/himem-options.com"
REJECT_PROBE="$OUT/himem-reject.com"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null || { echo "ERROR: missing $tool"; exit 1; }
done

nasm -f bin "$ROOT/tests/himem_options_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/himem_reject_probe.asm" -o "$REJECT_PROBE"
cp "$FLOPPY" "$IMAGE"
mdel -i "$IMAGE" ::HELP.HLP >/dev/null 2>&1 || true
mcopy -o -i "$IMAGE" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
mcopy -o -i "$IMAGE" "$PROBE" ::HIMOPT.COM
{
    printf 'DEVICE=A:\\HIMEM.SYS /HMAMIN=1 /NUMHANDLES=3 /INT15=128 /MACHINE:PS2 /A20CONTROL:ON /SHADOWRAM:OFF /CPUCLOCK:OFF\r\n'
} | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'HIMOPT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 25 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true

grep -Fq 'HIMEM_OPTIONS_PASS' "$LOG" || {
    sed -n '1,160p' "$LOG" >&2
    exit 1
}

for option in \
    '/HMAMIN=64' '/NUMHANDLES=0' '/NUMHANDLES=129' '/INT15=65536' \
    '/MACHINE:UNKNOWN' '/A20CONTROL:MAYBE' '/SHADOWRAM:MAYBE' '/CPUCLOCK:MAYBE'
do
    tag=$(printf '%s' "$option" | tr -c 'A-Za-z0-9' '_')
    reject_image="$OUT/floppy-himem-reject-$tag.img"
    reject_log="$OUT/himem-reject-$tag.log"
    cp "$FLOPPY" "$reject_image"
    mdel -i "$reject_image" ::HELP.HLP >/dev/null 2>&1 || true
    mcopy -o -i "$reject_image" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
    mcopy -o -i "$reject_image" "$REJECT_PROBE" ::HIMREJ.COM
    printf 'DEVICE=A:\\HIMEM.SYS %s\r\n' "$option" \
        | mcopy -o -i "$reject_image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\nCTTY AUX\r\nHIMREJ.COM\r\n'
    } | mcopy -o -i "$reject_image" - ::AUTOEXEC.BAT
    timeout 20 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$reject_image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$reject_log" 2>&1 || true
    grep -Fq HIMEM_REJECT_PASS "$reject_log" || {
        echo "HIMEM accepted invalid option: $option" >&2
        sed -n '1,100p' "$reject_log" >&2
        exit 1
    }
done

echo 'HIMEM documented option semantics and rejection boundaries passed'
