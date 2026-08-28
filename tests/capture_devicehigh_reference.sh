#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || ($2 != 5.0 && $2 != 6.22) ]]; then
    echo 'usage: capture_devicehigh_reference.sh BOOTABLE_FAT_IMAGE 5.0|6.22 OUTPUT_LOG' >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE_IMAGE=$1
DOS_VERSION=$2
OUTPUT_LOG=$3
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/msdos-devicehigh-reference.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing required tool: $tool" >&2
        exit 1
    }
done

nasm -f bin "$ROOT/tests/devicehigh_reference_driver.asm" -o "$WORK_DIR/DHREF.SYS"
nasm -f bin "$ROOT/tests/installhigh_reference_probe.asm" -o "$WORK_DIR/IHREF.COM"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$WORK_DIR/QEXIT.COM"

run_case() {
    local name=$1
    shift
    local image="$WORK_DIR/$name.img"
    local log="$WORK_DIR/$name.log"
    cp "$SOURCE_IMAGE" "$image"
    export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
    mcopy -o -i "$image" "$WORK_DIR/DHREF.SYS" ::DHREF.SYS
    mcopy -o -i "$image" "$WORK_DIR/IHREF.COM" ::IHREF.COM
    mcopy -o -i "$image" "$WORK_DIR/QEXIT.COM" ::QEXIT.COM
    {
        printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\n'
        printf 'DEVICE=A:\\EMM386.EXE NOEMS\r\n'
        for line in "$@"; do
            printf '%s\r\n' "$line"
        done
    } | mcopy -o -i "$image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'ECHO DEVICEHIGH_REF_BOOTED\r\n'
        printf 'QEXIT.COM\r\n'
    } | mcopy -o -i "$image" - ::AUTOEXEC.BAT
    timeout 30 qemu-system-i386 \
        -display none -monitor none \
        -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >"$log" 2>&1 || true
    printf 'CASE=%s\n' "$name"
    sed -n '/DEVICEHIGH_REF_SEG=/p;/INSTALLHIGH_REF_RAN/p;/DEVICEHIGH_REF_BOOTED/p;/[Uu]nrecognized/p;/[Ee]rror in CONFIG/p' "$log" | tr -d '\r'
    printf 'CASE_END=%s\n' "$name"
}

mkdir -p "$(dirname "$OUTPUT_LOG")"
{
    printf 'DEVICEHIGH_REFERENCE_BEGIN DOS=%s\n' "$DOS_VERSION"
    run_case device_low 'DOS=UMB' 'DEVICE=A:\DHREF.SYS LOW'
    run_case devicehigh 'DOS=UMB' 'DEVICEHIGH=A:\DHREF.SYS HIGH'
    run_case devicehigh_before_dos 'DEVICEHIGH=A:\DHREF.SYS BEFORE' 'DOS=UMB'
    run_case devicehigh_size 'DOS=UMB' 'DEVICEHIGH SIZE=200 A:\DHREF.SYS SIZE'
    if [[ $DOS_VERSION == 6.22 ]]; then
        run_case devicehigh_region 'DOS=UMB' 'DEVICEHIGH /L:1=A:\DHREF.SYS REGION'
        run_case devicehigh_region_s 'DOS=UMB' 'DEVICEHIGH /L:1,200 /S=A:\DHREF.SYS SHRINK'
    fi
    run_case installhigh 'DOS=UMB' 'INSTALLHIGH=A:\IHREF.COM ARG'
    printf 'DEVICEHIGH_REFERENCE_END DOS=%s\n' "$DOS_VERSION"
} >"$OUTPUT_LOG"

cat "$OUTPUT_LOG"
