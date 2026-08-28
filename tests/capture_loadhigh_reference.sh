#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo 'usage: capture_loadhigh_reference.sh MSDOS_622_BOOTABLE_IMAGE OUTPUT_LOG' >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE_IMAGE=$1
OUTPUT_LOG=$2
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/msdos-loadhigh-reference.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing required tool: $tool" >&2
        exit 1
    }
done

nasm -f bin "$ROOT/tests/loadhigh_child.asm" -o "$WORK_DIR/LHCHILD.COM"
nasm -f bin "$ROOT/tests/loadhigh_state.asm" -o "$WORK_DIR/LHSTATE.COM"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$WORK_DIR/QEXIT.COM"

run_case() {
    local name=$1
    local emm_options=$2
    local command=$3
    local image="$WORK_DIR/$name.img"
    local log="$WORK_DIR/$name.log"
    cp "$SOURCE_IMAGE" "$image"
    export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
    mcopy -o -i "$image" "$WORK_DIR/LHCHILD.COM" ::LHCHILD.COM
    mcopy -o -i "$image" "$WORK_DIR/LHSTATE.COM" ::LHSTATE.COM
    mcopy -o -i "$image" "$WORK_DIR/QEXIT.COM" ::QEXIT.COM
    {
        printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\n'
        printf 'DEVICE=A:\\EMM386.EXE %s\r\n' "$emm_options"
        printf 'DOS=UMB\r\n'
    } | mcopy -o -i "$image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'ECHO CASE_BEGIN_%s\r\n' "$name"
        printf '%s\r\n' "$command"
        printf 'LHSTATE.COM\r\n'
        printf 'ECHO CASE_END_%s\r\n' "$name"
        printf 'QEXIT.COM\r\n'
    } | mcopy -o -i "$image" - ::AUTOEXEC.BAT
    timeout 30 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >"$log" 2>&1 || true
    printf 'CASE=%s\n' "$name"
    sed -n \
        '/^CASE_BEGIN_/p;/^CHILD_/p;/^LOADHIGH_CHILD_END/p;/^PARENT_/p;/^LOADHIGH_STATE_END/p;/UMB number/p;/[Pp]arameter/p;/^CASE_END_/p' \
        "$log" | tr -d '\r'
    printf 'CASE_END=%s\n' "$name"
}

mkdir -p "$(dirname "$OUTPUT_LOG")"
{
    printf 'LOADHIGH_REFERENCE_BEGIN DOS=6.22\n'
    run_case region_1 'NOEMS' 'LOADHIGH /L:1 LHCHILD.COM'
    run_case invalid_region 'NOEMS' 'LOADHIGH /L:16 LHCHILD.COM'
    run_case minimum 'NOEMS' 'LOADHIGH /L:1,200 LHCHILD.COM'
    run_case shrink 'NOEMS' 'LOADHIGH /L:1,200 /S LHCHILD.COM'
    run_case shrink_without_list 'NOEMS' 'LOADHIGH /S LHCHILD.COM'
    run_case region_2 'NOEMS X=D000-D7FF' 'LOADHIGH /L:2 LHCHILD.COM'
    run_case region_list 'NOEMS X=D000-D7FF' 'LOADHIGH /L:1;2 LHCHILD.COM'
    run_case minimum_rejected 'NOEMS X=D000-D7FF' \
        'LOADHIGH /L:1,40000;2,10000 /S LHCHILD.COM'
    run_case minimum_accepted 'NOEMS X=D000-D7FF' \
        'LOADHIGH /L:1,10000;2,40000 /S LHCHILD.COM'
    printf 'LOADHIGH_REFERENCE_END DOS=6.22\n'
} >"$OUTPUT_LOG"

cat "$OUTPUT_LOG"
