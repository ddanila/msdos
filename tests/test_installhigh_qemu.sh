#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
FLOPPY="$OUT/floppy.img"
HIMEM="$OUT/installhigh-himem.sys"
TSR="$OUT/installhigh-tsr.com"
STATE="$OUT/installhigh-state.com"
QEXIT="$OUT/installhigh-exit.com"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done
[[ -f $FLOPPY ]] || {
    echo "ERROR: $FLOPPY not found — run 'make deploy' first" >&2
    exit 1
}

"$ROOT/bin/jwasm-bin" -Fo"$HIMEM" "$ROOT/MS-DOS/v4.0/src/DEV/HIMEM/HIMEM.ASM"
nasm -f bin "$ROOT/tests/installhigh_test_tsr.asm" -o "$TSR"
nasm -f bin "$ROOT/tests/loadhigh_state.asm" -o "$STATE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"

run_case() {
    local name=$1
    local provider=$2
    local image="$OUT/installhigh-$name.img"
    local log="$OUT/installhigh-$name.log"
    cp "$FLOPPY" "$image"
    export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
    mcopy -o -i "$image" "$TSR" ::IHREF.COM
    mcopy -o -i "$image" "$STATE" ::IHSTATE.COM
    mcopy -o -i "$image" "$QEXIT" ::QEXIT.COM
    if [[ $provider == yes ]]; then
        mcopy -o -i "$image" "$HIMEM" ::HIMEM.SYS
        {
            printf 'DEVICE=HIMEM.SYS\r\n'
            printf 'DEVICE=EMM386.SYS RAM M5\r\n'
            printf 'INSTALLHIGH=IHREF.COM TOKEN\r\n'
            printf 'DOS=UMB\r\n'
        } | mcopy -o -i "$image" - ::CONFIG.SYS
    else
        {
            printf 'DOS=UMB\r\n'
            printf 'INSTALLHIGH=IHREF.COM TOKEN\r\n'
        } | mcopy -o -i "$image" - ::CONFIG.SYS
    fi
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'IHSTATE.COM\r\n'
        printf 'ECHO INSTALLHIGH_BOOTED\r\n'
        printf 'QEXIT.COM\r\n'
    } | mcopy -o -i "$image" - ::AUTOEXEC.BAT
    rm -f "$log"
    timeout 35 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >"$log" 2>&1 || true
    printf '%s\n' "$log"
}

high_log=$(run_case high yes)
fallback_log=$(run_case fallback no)
high_segment=$(sed -n 's/.*INSTALLHIGH_TSR_SEG=\([0-9A-F][0-9A-F]*\).*/\1/p' "$high_log" | head -1)
fallback_segment=$(sed -n 's/.*INSTALLHIGH_TSR_SEG=\([0-9A-F][0-9A-F]*\).*/\1/p' "$fallback_log" | head -1)

if [[ -z $high_segment ]] \
    || (( 16#$high_segment < 16#8000 )) \
    || ! grep -q 'TAIL= TOKEN' "$high_log" \
    || ! grep -q '^PARENT_STRATEGY=0000' "$high_log" \
    || ! grep -q '^PARENT_UMB_LINK=0000' "$high_log" \
    || ! grep -q '^INSTALLHIGH_BOOTED' "$high_log"; then
    echo 'FAIL: INSTALLHIGH upper execution and restoration contract' >&2
    sed -n '1,180p' "$high_log" >&2
    exit 1
fi

if [[ -z $fallback_segment ]] \
    || (( 16#$fallback_segment >= 16#8000 )) \
    || ! grep -q 'TAIL= TOKEN' "$fallback_log" \
    || ! grep -q '^PARENT_STRATEGY=0000' "$fallback_log" \
    || ! grep -q '^PARENT_UMB_LINK=0000' "$fallback_log" \
    || ! grep -q '^INSTALLHIGH_BOOTED' "$fallback_log"; then
    echo 'FAIL: INSTALLHIGH conventional fallback contract' >&2
    sed -n '1,180p' "$fallback_log" >&2
    exit 1
fi

echo '  PASS: INSTALLHIGH TSR placement, tail, state restoration, and fallback'
