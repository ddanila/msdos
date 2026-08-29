#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo 'usage: verify_third_party_umb_provider.sh JEMMEX.EXE [OUTPUT_LOG]' >&2
    exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROVIDER=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
OUTPUT_LOG=${2:-$ROOT/out/third-party-umb-provider.log}
FLOPPY="$ROOT/out/floppy.img"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/msdos-third-party-umb.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

for tool in mcopy nasm qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "missing required tool: $tool" >&2
        exit 1
    }
done
[[ -f "$PROVIDER" ]] || { echo "missing provider: $PROVIDER" >&2; exit 1; }
[[ -f "$FLOPPY" ]] || { echo "missing image: $FLOPPY (run make deploy)" >&2; exit 1; }

nasm -f bin "$ROOT/tests/umb_lifecycle_reference.asm" -o "$WORK/UMBLREF.COM"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$WORK/QEXIT.COM"
cp "$FLOPPY" "$WORK/provider.img"
mcopy -o -i "$WORK/provider.img" "$PROVIDER" ::JEMMEX.EXE
mcopy -o -i "$WORK/provider.img" "$WORK/UMBLREF.COM" ::UMBLREF.COM
mcopy -o -i "$WORK/provider.img" "$WORK/QEXIT.COM" ::QEXIT.COM
{
    printf 'DEVICE=A:\\JEMMEX.EXE NOEMS\r\n'
    printf 'DOS=UMB\r\n'
} | mcopy -o -i "$WORK/provider.img" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'UMBLREF.COM\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$WORK/provider.img" - ::AUTOEXEC.BAT

mkdir -p "$(dirname "$OUTPUT_LOG")"
timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$WORK/provider.img",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$OUTPUT_LOG" 2>&1 || true

for expected in \
    'LINK C=0' 'STRATEGY_0040 C=0' 'ALLOC_0010 C=0' \
    'GROW_FFFF C=1 AX=0008' 'UNLINK_LIVE C=0' 'LIVE_VALUE=5AA5' \
    'RELINK_LIVE C=0' 'FREE_LIVE C=0' 'ALLOC_EXACT_LARGEST C=0' \
    'UPPER_NO_FALLBACK C=1 AX=0008' 'UPPER_THEN_LOW C=0' \
    'UMB_LIFECYCLE_END'
do
    grep -Fq "$expected" "$OUTPUT_LOG" || {
        echo "third-party UMB provider contract missing: $expected" >&2
        sed -n '1,220p' "$OUTPUT_LOG" >&2
        exit 1
    }
done

echo '  PASS: independent JemmEx provider interoperates through standard XMS UMB services'
