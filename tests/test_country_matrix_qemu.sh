#!/bin/bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
QEXIT="$OUT/country-matrix-qexit.com"
PASS=0
FAIL=0

[[ -f "$BASE" ]] || { echo "missing $BASE; run make deploy" >&2; exit 1; }
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"

for spec in 055:850 038:852 042:852 048:852 036:852; do
    country="${spec%%:*}"
    page="${spec##*:}"
    numeric=$((10#$country))
    image="$OUT/country-$country.img"
    probe="$OUT/country-$country.com"
    log="$OUT/country-$country.log"
    cp "$BASE" "$image"
    nasm -f bin -DCOUNTRY_ID="$numeric" "$ROOT/tests/country_config_probe.asm" -o "$probe"
    mcopy -o -i "$image" "$probe" ::CNTRYCHK.COM
    mcopy -o -i "$image" "$QEXIT" ::QEXIT.COM
    printf 'COUNTRY=%s,%s,COUNTRY.SYS\r\n' "$country" "$page" |
        mcopy -o -i "$image" - ::CONFIG.SYS
    printf '@ECHO OFF\r\nCTTY AUX\r\nCNTRYCHK.COM\r\nQEXIT.COM\r\n' |
        mcopy -o -i "$image" - ::AUTOEXEC.BAT
    timeout 20 qemu-system-i386 -display none \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -m 4 -serial stdio \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        </dev/null >"$log" 2>&1 || true
    if grep -q COUNTRY_CONFIG_PASS "$log" &&
       ! grep -q COUNTRY_CONFIG_FAIL "$log"; then
        echo "  PASS: COUNTRY=$country,$page loads the retail DOS 5 record"
        PASS=$((PASS+1))
    else
        echo "  FAIL: COUNTRY=$country,$page"
        FAIL=$((FAIL+1))
    fi
done

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
