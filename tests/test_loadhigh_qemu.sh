#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
FLOPPY="$OUT/floppy.img"
HIMEM="$OUT/loadhigh-himem.sys"
COM_CHILD="$OUT/loadhigh-child.com"
EXE_CHILD="$OUT/loadhigh-child.exe"
STATE="$OUT/loadhigh-state.com"
QEXIT="$OUT/loadhigh-qexit.com"

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

"$ROOT/bin/jwasm-bin" -Fo"$HIMEM" "$ROOT/MS-DOS/v4.0/src/DEV/HIMEM/HIMEM.ASM"
nasm -f bin "$ROOT/tests/loadhigh_child.asm" -o "$COM_CHILD"
nasm -f bin "$ROOT/tests/loadhigh_exe_child.asm" -o "$EXE_CHILD"
nasm -f bin "$ROOT/tests/loadhigh_state.asm" -o "$STATE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"

run_image() {
    local name=$1
    local config=$2
    local commands=$3
    local image="$OUT/floppy-loadhigh-$name.img"
    local log="$OUT/loadhigh-$name.log"

    cp "$FLOPPY" "$image"
    mcopy -o -i "$image" "$HIMEM" ::HIMEM.SYS
    mcopy -o -i "$image" "$COM_CHILD" ::LHCHILD.COM
    mcopy -o -i "$image" "$EXE_CHILD" ::LHEXEC.EXE
    mcopy -o -i "$image" "$STATE" ::LHSTATE.COM
    mcopy -o -i "$image" "$QEXIT" ::QEXIT.COM
    printf '%s' "$config" | mcopy -o -i "$image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf '%s' "$commands"
        printf '\r\n'
        printf 'QEXIT.COM\r\n'
    } | mcopy -o -i "$image" - ::AUTOEXEC.BAT
    timeout "${QEMU_TIMEOUT_SECONDS:-45}" qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$log" 2>&1 || true
}

provider_commands=$(printf '%b' \
    'ECHO PROVIDER_BEGIN\r\n' \
    'LHSTATE.COM\r\n' \
    'LHCHILD.COM\r\n' \
    'LOADHIGH LHCHILD.COM\r\n' \
    'LHSTATE.COM\r\n' \
    'LH LHCHILD.COM\r\n' \
    'LHSTATE.COM\r\n' \
    'LHEXEC.EXE\r\n' \
    'LOADHIGH LHEXEC.EXE\r\n' \
    'LHSTATE.COM\r\n' \
    'LOADHIGH\r\n' \
    'LOADHIGH VER\r\n' \
    'LOADHIGH MISSING.COM\r\n' \
    'LHSTATE.COM\r\n' \
    'ECHO PROVIDER_END\r\n')
provider_config=$(printf '%b' \
    'DEVICE=A:\\HIMEM.SYS\r\n' \
    'DEVICE=A:\\EMM386.SYS M5\r\n' \
    'DOS=UMB\r\n')
run_image provider "$provider_config" "$provider_commands"

provider_log="$OUT/loadhigh-provider.log"
if [[ $(grep -Ec '^CHILD_PSP=[A-F][0-9A-F]{3}' "$provider_log") -ne 2 ]] \
    || ! grep -Eq '^CHILD_PSP=[0-9][0-9A-F]{3}' "$provider_log" \
    || [[ $(grep -c '^CHILD_STRATEGY=0080' "$provider_log") -ne 2 ]] \
    || [[ $(grep -c '^CHILD_UMB_LINK=0001' "$provider_log") -ne 3 ]] \
    || ! grep -Eq '^EXE_PSP=[A-F][0-9A-F]{3}' "$provider_log" \
    || ! grep -q '^EXE_STRATEGY=0080' "$provider_log" \
    || ! grep -q '^EXE_UMB_LINK=0001' "$provider_log" \
    || [[ $(grep -c '^PARENT_STRATEGY=0000' "$provider_log") -ne 5 ]] \
    || [[ $(grep -c '^PARENT_UMB_LINK=0001' "$provider_log") -ne 5 ]] \
    || ! grep -q 'Required parameter missing' "$provider_log" \
    || [[ $(grep -c 'File not found' "$provider_log") -lt 2 ]] \
    || ! grep -q '^PROVIDER_END' "$provider_log"
then
    echo "FAIL: LOADHIGH/LH provider contract" >&2
    sed -n '1,220p' "$provider_log" >&2
    exit 1
fi

fallback_commands=$(printf '%b' \
    'ECHO FALLBACK_BEGIN\r\n' \
    'LOADHIGH LHCHILD.COM\r\n' \
    'LHSTATE.COM\r\n' \
    'ECHO FALLBACK_END\r\n')
run_image fallback '' "$fallback_commands"
fallback_log="$OUT/loadhigh-fallback.log"
if ! grep -Eq '^CHILD_PSP=[0-9][0-9A-F]{3}' "$fallback_log" \
    || ! grep -q '^CHILD_STRATEGY=0080' "$fallback_log" \
    || ! grep -q '^CHILD_UMB_LINK=0000' "$fallback_log" \
    || ! grep -q '^PARENT_STRATEGY=0000' "$fallback_log" \
    || ! grep -q '^PARENT_UMB_LINK=0000' "$fallback_log" \
    || ! grep -q '^FALLBACK_END' "$fallback_log"
then
    echo "FAIL: LOADHIGH conventional fallback contract" >&2
    sed -n '1,160p' "$fallback_log" >&2
    exit 1
fi

high_commands=$(printf '%b' \
    'ECHO DOS_HIGH_BEGIN\r\n' \
    'LOADHIGH LHCHILD.COM\r\n' \
    'LHSTATE.COM\r\n' \
    'ECHO DOS_HIGH_END\r\n')
high_config=$(printf '%b' \
    'DEVICE=A:\\HIMEM.SYS\r\n' \
    'DEVICE=A:\\EMM386.SYS M5\r\n' \
    'DOS=HIGH,UMB\r\n')
run_image high "$high_config" "$high_commands"
high_log="$OUT/loadhigh-high.log"
if ! grep -Eq '^CHILD_PSP=[A-F][0-9A-F]{3}' "$high_log" \
    || ! grep -q '^CHILD_STRATEGY=0080' "$high_log" \
    || ! grep -q '^CHILD_UMB_LINK=0001' "$high_log" \
    || ! grep -q '^PARENT_STRATEGY=0000' "$high_log" \
    || ! grep -q '^PARENT_UMB_LINK=0001' "$high_log" \
    || ! grep -q '^DOS_HIGH_END' "$high_log"
then
    echo "FAIL: LOADHIGH with DOS=HIGH" >&2
    sed -n '1,180p' "$high_log" >&2
    exit 1
fi

echo "  PASS: LOADHIGH/LH COM, EXE, fallback, restoration, and DOS=HIGH contracts"
