#!/bin/bash

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/floppy-smartdrv-dos6.img"
HDD_IMG="$OUT/smartdrv-dos6-hdd.img"
SERIAL_LOG="$OUT/smartdrv-dos6.log"
EXIT_COM="$OUT/smartdrv-dos6-exit.com"
IO_COM="$OUT/smartdrv-dos6-io.com"

[[ -f "$FLOPPY" ]] || { echo "ERROR: run 'make deploy' first"; exit 1; }
for tool in mcopy mformat nasm python3 qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing $tool"; exit 1; }
done

cp "$FLOPPY" "$BOOT_IMG"
dd if=/dev/zero of="$HDD_IMG" bs=512 count=32256 status=none
python3 -c "
import struct
p=bytearray(512); p[446:462]=bytes((0,1,1,0,6,0,63,31))+struct.pack('<II',63,31248); p[510:512]=b'\x55\xaa'
with open('$HDD_IMG','r+b') as f: f.write(p)
"
mformat -i "$HDD_IMG@@32256" -t 31 -h 16 -n 63 -H 63 -c 4 ::
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
nasm -f bin "$REPO_ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
nasm -f bin "$REPO_ROOT/tests/smartdrv_io_probe.asm" -o "$IO_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
mcopy -o -i "$BOOT_IMG" "$IO_COM" ::SDIO.COM
printf 'DEVICE=SMARTDRV.SYS 256\r\n' | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'SMARTDRV /?\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_HELP_FAILED\r\n'
    printf 'SMARTDRV C+ /F /S\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_CONFIG_FAILED\r\n'
    printf 'SDIO.COM\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_IO_FAILED\r\n'
    printf 'ECHO SMARTDRV_DIRTY_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_DIRTY_END\r\n'
    printf 'SMARTDRV /C\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_FLUSH_FAILED\r\n'
    printf 'ECHO SMARTDRV_CLEAN_BEGIN\r\nSMARTDRV /S\r\nECHO SMARTDRV_CLEAN_END\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

: >"$SERIAL_LOG"
timeout 25 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=ide,index=0,format=raw,file="$HDD_IMG",cache=writethrough \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 -boot a -serial stdio -no-reboot \
    >"$SERIAL_LOG" 2>&1 || true

dirty="$(sed -n '/SMARTDRV_DIRTY_BEGIN/,/SMARTDRV_DIRTY_END/p' "$SERIAL_LOG")"
clean="$(sed -n '/SMARTDRV_CLEAN_BEGIN/,/SMARTDRV_CLEAN_END/p' "$SERIAL_LOG")"
sector_matches="$(python3 - "$HDD_IMG" <<'PY'
import sys
with open(sys.argv[1], 'rb') as f:
    f.seek((63 + 1000) * 512); actual=f.read(512)
expected=b'SMARTDRV_SECTOR_OK'+bytes([0xA5])*(512-len(b'SMARTDRV_SECTOR_OK'))
print('yes' if actual == expected else 'no')
PY
)"

if grep -q 'C:  Read cache yes  Write cache yes' "$SERIAL_LOG" \
    && grep -Eq '[1-9][0-9]* dirty' <<<"$dirty" \
    && grep -q '0 dirty' <<<"$clean" \
    && [[ "$sector_matches" == yes ]] \
    && ! grep -q 'SMARTDRV_.*_FAILED\|SMARTDRV: ' "$SERIAL_LOG"; then
    echo "  PASS: DOS 6 SMARTDRV policy delayed and explicitly flushed a fixed-disk write"
    exit 0
fi

echo "  FAIL: DOS 6 SMARTDRV controller/write-behind contract did not complete"
sed -n '1,220p' "$SERIAL_LOG"
exit 1
