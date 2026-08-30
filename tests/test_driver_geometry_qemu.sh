#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
FLOPPY=${FLOPPY_IMAGE:-$OUT/floppy.img}

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done
[[ -f "$FLOPPY" ]] || {
    echo "ERROR: $FLOPPY not found — run 'make deploy' first" >&2
    exit 1
}

# option:type:tracks:sectors/track:heads:total sectors
cases=(
    '/F:0:0:40:9:2:720'
    '/F:1:1:80:15:2:2400'
    '/F:2:2:80:9:2:1440'
    '/F:7:7:80:18:2:2880'
    '/F:9:9:80:36:2:5760'
)

for spec in "${cases[@]}"; do
    IFS=: read -r switch factor type tracks spt heads total <<<"$spec"
    option="$switch:$factor"
    name="f$factor"
    image="$OUT/floppy-driver-geometry-$name.img"
    probe="$OUT/driver-geometry-$name.com"
    log="$OUT/driver-geometry-$name.log"
    nasm -f bin -DEXPECT_TYPE="$type" -DEXPECT_TRACKS="$tracks" \
        -DEXPECT_SPT="$spt" -DEXPECT_HEADS="$heads" \
        -DEXPECT_TOTAL="$total" "$ROOT/tests/driver_geometry_probe.asm" \
        -o "$probe"
    cp "$FLOPPY" "$image"
    mcopy -o -i "$image" "$probe" ::GEOMETRY.COM
    {
        printf 'DEVICE=A:\\DRIVER.SYS /D:1 %s\r\n' "$option"
        printf 'LASTDRIVE=Z\r\n'
    } | mcopy -o -i "$image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'GEOMETRY.COM\r\n'
    } | mcopy -o -i "$image" - ::AUTOEXEC.BAT
    timeout 25 qemu-system-i386 -display none -monitor none \
        -machine pc -cpu 486 -m 4 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$log" 2>&1 || true
    if ! grep -Fq 'DRIVER_GEOMETRY_PASS' "$log"; then
        echo "FAIL: DRIVER.SYS $option geometry" >&2
        sed -n '1,100p' "$log" >&2
        exit 1
    fi
done

echo '  PASS: DRIVER.SYS exposes every documented /F geometry'
