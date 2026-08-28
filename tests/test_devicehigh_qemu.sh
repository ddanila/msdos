#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
FLOPPY="$OUT/floppy.img"

if [[ ! -f $FLOPPY ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first" >&2
    exit 1
fi

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done

DRIVER="$OUT/devicehigh-ref.sys"
HIMEM="$OUT/devicehigh-himem.sys"
HIGH_PROBE="$OUT/devicehigh-state.com"
LOW_PROBE="$OUT/devicehigh-fallback-state.com"
LINKED_LOW_PROBE="$OUT/devicehigh-linked-fallback-state.com"
QEXIT="$OUT/devicehigh-exit.com"
"$ROOT/bin/jwasm-bin" -Fo"$HIMEM" "$ROOT/MS-DOS/v4.0/src/DEV/HIMEM/HIMEM.ASM"
nasm -f bin "$ROOT/tests/devicehigh_reference_driver.asm" -o "$DRIVER"
nasm -DEXPECT_HIGH=1 -f bin "$ROOT/tests/devicehigh_state_probe.asm" -o "$HIGH_PROBE"
nasm -DEXPECT_HIGH=0 -f bin "$ROOT/tests/devicehigh_state_probe.asm" -o "$LOW_PROBE"
nasm -DEXPECT_HIGH=0 -DEXPECT_LINK=1 -f bin \
    "$ROOT/tests/devicehigh_state_probe.asm" -o "$LINKED_LOW_PROBE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"

run_case() {
    local name=$1
    local with_provider=$2
    local image="$OUT/devicehigh-$name.img"
    local log="$OUT/devicehigh-$name.log"
    cp "$FLOPPY" "$image"
    export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
    mcopy -o -i "$image" "$DRIVER" ::DHREF.SYS
    mcopy -o -i "$image" "$QEXIT" ::QEXIT.COM
    if [[ $with_provider == yes ]]; then
        mcopy -o -i "$image" "$HIMEM" ::HIMEM.SYS
        mcopy -o -i "$image" "$ROOT/MS-DOS/v4.0/src/MEMM/MEMM/EMM386.SYS" ::EMM386.SYS
        if [[ $name == region-missing || $name == region-shrink || $name == region-min-large ]]; then
            mcopy -o -i "$image" "$LINKED_LOW_PROBE" ::DHSTATE.COM
        else
            mcopy -o -i "$image" "$HIGH_PROBE" ::DHSTATE.COM
        fi
        {
            printf 'DEVICE=HIMEM.SYS\r\n'
            printf 'DEVICE=EMM386.SYS M5\r\n'
            if [[ $name == size ]]; then
                printf 'DEVICEHIGH SIZE=0200 DHREF.SYS SIZEARG\r\n'
            elif [[ $name == region ]]; then
                printf 'DEVICEHIGH /L:1=DHREF.SYS REGION1\r\n'
            elif [[ $name == region-missing ]]; then
                printf 'DEVICEHIGH /L:16=DHREF.SYS REGION16\r\n'
            elif [[ $name == region-min ]]; then
                printf 'DEVICEHIGH /L:1,200=DHREF.SYS REGIONMIN\r\n'
            elif [[ $name == region-shrink ]]; then
                printf 'DEVICEHIGH /L:1,200 /S=DHREF.SYS SHRINK\r\n'
            elif [[ $name == region-min-large ]]; then
                printf 'DEVICEHIGH /L:1,65535=DHREF.SYS MINLARGE\r\n'
            else
                printf 'DEVICEHIGH=DHREF.SYS BEFORE\r\n'
            fi
            printf 'DOS=UMB\r\n'
        } | mcopy -o -i "$image" - ::CONFIG.SYS
        {
            printf '@ECHO OFF\r\nCTTY AUX\r\nDHSTATE.COM\r\nQEXIT.COM\r\n'
        } | mcopy -o -i "$image" - ::AUTOEXEC.BAT
    else
        mcopy -o -i "$image" "$LOW_PROBE" ::DHSTATE.COM
        {
            printf 'DOS=UMB\r\n'
            printf 'DEVICEHIGH=DHREF.SYS FALLBACK\r\n'
        } | mcopy -o -i "$image" - ::CONFIG.SYS
        {
            printf '@ECHO OFF\r\nCTTY AUX\r\nDHSTATE.COM\r\nQEXIT.COM\r\n'
        } | mcopy -o -i "$image" - ::AUTOEXEC.BAT
    fi
    rm -f "$log"
    timeout 35 qemu-system-i386 \
        -display none -monitor none \
        -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >"$log" 2>&1 || true
    printf '%s\n' "$log"
}

high_log=$(run_case high yes)
size_log=$(run_case size yes)
region_log=$(run_case region yes)
region_missing_log=$(run_case region-missing yes)
region_min_log=$(run_case region-min yes)
region_shrink_log=$(run_case region-shrink yes)
region_min_large_log=$(run_case region-min-large yes)
fallback_log=$(run_case fallback no)

if ! grep -q '^DEVICEHIGH_STATE_PASS' "$high_log"; then
    echo 'FAIL: DEVICEHIGH did not retain the driver in an upper arena' >&2
    sed -n '1,160p' "$high_log" >&2
    exit 1
fi

if ! grep -q '^DEVICEHIGH_STATE_PASS' "$size_log"; then
    echo 'FAIL: DEVICEHIGH SIZE= did not place the driver high' >&2
    sed -n '1,160p' "$size_log" >&2
    exit 1
fi

if ! grep -q '^DEVICEHIGH_STATE_PASS' "$region_log"; then
    echo 'FAIL: DEVICEHIGH /L:1 did not select the first UMB region' >&2
    sed -n '1,160p' "$region_log" >&2
    exit 1
fi

if ! grep -q '^DEVICEHIGH_FALLBACK_PASS' "$region_missing_log"; then
    echo 'FAIL: DEVICEHIGH unavailable /L region did not fall back low' >&2
    sed -n '1,160p' "$region_missing_log" >&2
    exit 1
fi

if ! grep -q '^DEVICEHIGH_STATE_PASS' "$region_min_log"; then
    echo 'FAIL: DEVICEHIGH /L minimum-size region did not load high' >&2
    sed -n '1,160p' "$region_min_log" >&2
    exit 1
fi

if ! grep -q '^DEVICEHIGH_FALLBACK_PASS' "$region_shrink_log"; then
    echo 'FAIL: DEVICEHIGH /S did not shrink the selected UMB before loading' >&2
    sed -n '1,160p' "$region_shrink_log" >&2
    exit 1
fi

if ! grep -q '^DEVICEHIGH_FALLBACK_PASS' "$region_min_large_log"; then
    echo 'FAIL: DEVICEHIGH oversized region minimum did not fall back low' >&2
    sed -n '1,160p' "$region_min_large_log" >&2
    exit 1
fi

if ! grep -q '^DEVICEHIGH_FALLBACK_PASS' "$fallback_log"; then
    echo 'FAIL: DEVICEHIGH did not fall back to conventional memory' >&2
    sed -n '1,160p' "$fallback_log" >&2
    exit 1
fi

echo '  PASS: DEVICEHIGH upper placement, DOS= ordering, retained link, and fallback'
