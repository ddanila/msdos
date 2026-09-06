#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
HIMEM="$OUT/loadhigh-himem.sys"
COM_CHILD="$OUT/loadhigh-child.com"
EXE_CHILD="$OUT/loadhigh-child.exe"
STATE="$OUT/loadhigh-state.com"
ERROR_CHILD="$OUT/loadhigh-error.com"
CTRLC_CHILD="$OUT/loadhigh-ctrlc.com"
QEXIT="$OUT/loadhigh-qexit.com"
TSR_CHILD="$OUT/loadhigh-tsr.com"
TSR_TRIGGER="$OUT/loadhigh-tsr-trigger.com"

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

"$ROOT/bin/jwasm-bin" -Fo"$HIMEM" "$ROOT/src/DEV/HIMEM/HIMEM.ASM"
nasm -f bin "$ROOT/tests/loadhigh_child.asm" -o "$COM_CHILD"
nasm -f bin "$ROOT/tests/loadhigh_exe_child.asm" -o "$EXE_CHILD"
nasm -f bin "$ROOT/tests/loadhigh_state.asm" -o "$STATE"
nasm -f bin "$ROOT/tests/loadhigh_error_child.asm" -o "$ERROR_CHILD"
nasm -f bin "$ROOT/tests/loadhigh_ctrlc_child.asm" -o "$CTRLC_CHILD"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
nasm -f bin "$ROOT/tests/loadhigh_tsr_child.asm" -o "$TSR_CHILD"
nasm -f bin "$ROOT/tests/loadhigh_tsr_trigger.asm" -o "$TSR_TRIGGER"

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
    mcopy -o -i "$image" "$ERROR_CHILD" ::LHERR.COM
    mcopy -o -i "$image" "$CTRLC_CHILD" ::LHCTRL.COM
    mcopy -o -i "$image" "$QEXIT" ::QEXIT.COM
    mcopy -o -i "$image" "$TSR_CHILD" ::LHTSR.COM
    mcopy -o -i "$image" "$TSR_TRIGGER" ::LHTRIG.COM
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
    'ECHO LH_OPTIONS_BEGIN\r\n' \
    'ECHO LH_REGION_1\r\n' \
    'LOADHIGH /L:1 LHCHILD.COM\r\n' \
    'ECHO LH_REGION_INVALID\r\n' \
    'LOADHIGH /L:16 LHCHILD.COM\r\n' \
    'ECHO LH_MINIMUM\r\n' \
    'LOADHIGH /L:1,200 LHCHILD.COM\r\n' \
    'ECHO LH_SHRINK\r\n' \
    'LOADHIGH /L:1,200 /S LHCHILD.COM\r\n' \
    'ECHO LH_SHRINK_ALONE\r\n' \
    'LOADHIGH /S LHCHILD.COM\r\n' \
    'ECHO LH_PROFILE_FAILURE\r\n' \
    'LOADHIGH /L:1,200 /S MISSING.COM\r\n' \
    'ECHO LH_PROFILE_RECOVERY\r\n' \
    'LOADHIGH /L:1 LHCHILD.COM\r\n' \
    'LHSTATE.COM\r\n' \
    'ECHO LH_OPTIONS_END\r\n' \
    'ECHO LH_PATHS_BEGIN\r\n' \
    'LOADHIGH /L:1 LHCHILD.COM "TWO WORDS" >LHOUT.TXT\r\n' \
    'TYPE LHOUT.TXT\r\n' \
    'LOADHIGH /L:1 LHERR.COM\r\n' \
    'IF ERRORLEVEL 37 ECHO LH_ERRORLEVEL_PASS\r\n' \
    'LHSTATE.COM\r\n' \
    'COMMAND /C LOADHIGH /L:1 LHCTRL.COM\r\n' \
    'LHSTATE.COM\r\n' \
    'LOADHIGH /L:1 LHCHILD.COM RECOVER\r\n' \
    'ECHO LH_PATHS_END\r\n' \
    'ECHO LH_TSR_BEGIN\r\n' \
    'LOADHIGH /L:1 LHTSR.COM\r\n' \
    'IF ERRORLEVEL 42 ECHO LH_TSR_ERRORLEVEL_PASS\r\n' \
    'LHTRIG.COM\r\n' \
    'LHSTATE.COM\r\n' \
    'ECHO LH_TSR_END\r\n' \
    'ECHO PROVIDER_END\r\n')
provider_config=$(printf '%b' \
    'DEVICE=A:\\HIMEM.SYS\r\n' \
    'DEVICE=A:\\EMM386.EXE RAM M5\r\n' \
    'DOS=UMB\r\n')
run_image provider "$provider_config" "$provider_commands"

provider_log="$OUT/loadhigh-provider.log"
options_log=$(sed -n '/^LH_OPTIONS_BEGIN/,/^LH_OPTIONS_END/p' "$provider_log")
invalid_log=$(sed -n '/^LH_REGION_INVALID/,/^LH_MINIMUM/p' "$provider_log")
shrink_log=$(sed -n '/^LH_SHRINK/,/^LH_SHRINK_ALONE/p' "$provider_log")
recovery_log=$(sed -n '/^LH_PROFILE_FAILURE/,/^LH_OPTIONS_END/p' "$provider_log")
paths_log=$(sed -n '/^LH_PATHS_BEGIN/,/^LH_PATHS_END/p' "$provider_log")
tsr_log=$(sed -n '/^LH_TSR_BEGIN/,/^LH_TSR_END/p' "$provider_log")
if [[ $(grep -Ec '^CHILD_PSP=[A-F][0-9A-F]{3}' "$provider_log") -ne 8 ]] \
    || [[ $(grep -Ec '^CHILD_PSP=[0-9][0-9A-F]{3}' "$provider_log") -ne 2 ]] \
    || [[ $(grep -c '^CHILD_STRATEGY=0080' "$provider_log") -ne 9 ]] \
    || [[ $(grep -c '^CHILD_UMB_LINK=0001' "$provider_log") -ne 9 ]] \
    || ! grep -Eq '^EXE_PSP=[A-F][0-9A-F]{3}' "$provider_log" \
    || ! grep -q '^EXE_STRATEGY=0080' "$provider_log" \
    || ! grep -q '^EXE_UMB_LINK=0001' "$provider_log" \
    || [[ $(grep -c 'PARENT_STRATEGY=0000' "$provider_log") -ne 9 ]] \
    || [[ $(grep -c '^PARENT_UMB_LINK=0000' "$provider_log") -ne 9 ]] \
    || ! grep -q 'Required parameter missing' "$provider_log" \
    || [[ $(grep -c 'File not found' "$provider_log") -lt 3 ]] \
    || [[ $(grep -c '^LOADHIGH_CHILD_END' <<<"$options_log") -ne 5 ]] \
    || ! grep -q 'A bad UMB number has been specified' <<<"$invalid_log" \
    || grep -q '^LOADHIGH_CHILD_END' <<<"$invalid_log" \
    || ! grep -Eq '^CHILD_PSP=[0-9][0-9A-F]{3}' <<<"$shrink_log" \
    || ! grep -q 'File not found' <<<"$recovery_log" \
    || ! grep -Eq '^CHILD_PSP=[A-F][0-9A-F]{3}' <<<"$recovery_log" \
    || ! grep -q '^CHILD_TAIL= "TWO WORDS"' <<<"$paths_log" \
    || ! grep -q '^LOADHIGH_ERROR_CHILD' <<<"$paths_log" \
    || ! grep -q '^LH_ERRORLEVEL_PASS' <<<"$paths_log" \
    || grep -q '^LOADHIGH_CTRLC_RETURNED' <<<"$paths_log" \
    || ! grep -q '^CHILD_TAIL= RECOVER' <<<"$paths_log" \
    || ! grep -Eq '^LOADHIGH_TSR_PSP=[A-F][0-9A-F]{3}' <<<"$tsr_log" \
    || ! grep -q '^LH_TSR_ERRORLEVEL_PASS' <<<"$tsr_log" \
    || ! grep -q '^LOADHIGH_TSR_HANDLER_PASS' <<<"$tsr_log" \
    || ! grep -q '^LOADHIGH_TSR_TRIGGER_PASS' <<<"$tsr_log" \
    || ! grep -q '^PROVIDER_END' "$provider_log"
then
    echo "FAIL: LOADHIGH/LH provider contract" >&2
    sed -n '1,220p' "$provider_log" >&2
    exit 1
fi

regions_commands=$(printf '%b' \
    'ECHO REGIONS_BEGIN\r\n' \
    'ECHO REGION_ONE\r\n' \
    'LOADHIGH /L:1 LHCHILD.COM\r\n' \
    'ECHO REGION_TWO\r\n' \
    'LOADHIGH /L:2 LHCHILD.COM\r\n' \
    'ECHO REGION_LIST\r\n' \
    'LOADHIGH /L:1;2 LHCHILD.COM\r\n' \
    'ECHO REGION_MIN_REJECT\r\n' \
    'LOADHIGH /L:1,40000;2,40000 /S LHCHILD.COM\r\n' \
    'ECHO REGION_MIN_ACCEPT\r\n' \
    'LOADHIGH /L:1,10000;2,10000 /S LHCHILD.COM\r\n' \
    'LHSTATE.COM\r\n' \
    'ECHO REGIONS_END\r\n')
regions_config=$(printf '%b' \
    'DEVICE=A:\\HIMEM.SYS\r\n' \
    'DEVICE=A:\\EMM386.EXE RAM M5 I=CC00-CFFF I=E400-E7FF\r\n' \
    'DOS=UMB\r\n')
run_image regions "$regions_config" "$regions_commands"
regions_log="$OUT/loadhigh-regions.log"
region_one_log=$(sed -n '/^REGION_ONE/,/^REGION_TWO/p' "$regions_log")
region_two_log=$(sed -n '/^REGION_TWO/,/^REGION_LIST/p' "$regions_log")
region_list_log=$(sed -n '/^REGION_LIST/,/^REGION_MIN_REJECT/p' "$regions_log")
region_reject_log=$(sed -n '/^REGION_MIN_REJECT/,/^REGION_MIN_ACCEPT/p' "$regions_log")
region_accept_log=$(sed -n '/^REGION_MIN_ACCEPT/,/^REGIONS_END/p' "$regions_log")
region_one_psp=$(sed -n 's/^CHILD_PSP=\([0-9A-F][0-9A-F]*\).*/\1/p' <<<"$region_one_log")
region_two_psp=$(sed -n 's/^CHILD_PSP=\([0-9A-F][0-9A-F]*\).*/\1/p' <<<"$region_two_log")
if [[ -z $region_one_psp || -z $region_two_psp || $region_one_psp == "$region_two_psp" ]] \
    || (( 16#$region_one_psp < 16#8000 || 16#$region_two_psp < 16#8000 )) \
    || ! grep -Eq '^CHILD_PSP=[A-F][0-9A-F]{3}' <<<"$region_list_log" \
    || ! grep -Eq '^CHILD_PSP=[0-9][0-9A-F]{3}' <<<"$region_reject_log" \
    || ! grep -q '^CHILD_STRATEGY=0000' <<<"$region_reject_log" \
    || ! grep -q '^CHILD_UMB_LINK=0000' <<<"$region_reject_log" \
    || ! grep -Eq '^CHILD_PSP=[A-F][0-9A-F]{3}' <<<"$region_accept_log" \
    || ! grep -q '^CHILD_STRATEGY=0080' <<<"$region_accept_log" \
    || ! grep -q '^CHILD_UMB_LINK=0001' <<<"$region_accept_log" \
    || ! grep -q '^PARENT_STRATEGY=0000' "$regions_log" \
    || ! grep -q '^PARENT_UMB_LINK=0000' "$regions_log" \
    || ! grep -q '^REGIONS_END' "$regions_log"
then
    echo "FAIL: LOADHIGH multi-region and per-region minimum contract" >&2
    sed -n '1,240p' "$regions_log" >&2
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
    'DEVICE=A:\\EMM386.EXE RAM M5\r\n' \
    'DOS=HIGH,UMB\r\n')
run_image high "$high_config" "$high_commands"
high_log="$OUT/loadhigh-high.log"
if ! grep -Eq '^CHILD_PSP=[A-F][0-9A-F]{3}' "$high_log" \
    || ! grep -q '^CHILD_STRATEGY=0080' "$high_log" \
    || ! grep -q '^CHILD_UMB_LINK=0001' "$high_log" \
    || ! grep -q '^PARENT_STRATEGY=0000' "$high_log" \
    || ! grep -q '^PARENT_UMB_LINK=0000' "$high_log" \
    || ! grep -q '^DOS_HIGH_END' "$high_log"
then
    echo "FAIL: LOADHIGH with DOS=HIGH" >&2
    sed -n '1,180p' "$high_log" >&2
    exit 1
fi

echo "  PASS: LOADHIGH/LH regions, minima, shrinking, fallback, restoration, and DOS=HIGH"
