#!/bin/bash

set -uo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT_IMG="$OUT/floppy-smartdrv-reboot.img"
HDD_IMG="$OUT/smartdrv-reboot-hdd.img"
LOG="$OUT/smartdrv-reboot.log"
EXIT_COM="$OUT/smartdrv-reboot-exit.com"
REBOOT_COM="$OUT/smartdrv-reboot.com"
IO_COM="$OUT/smartdrv-reboot-io.com"

for tool in mcopy mformat nasm python3 qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing $tool"; exit 1; }
done
[[ -f "$BASE" ]] || { echo "ERROR: run make deploy first"; exit 1; }

cp "$BASE" "$BOOT_IMG"
dd if=/dev/zero of="$HDD_IMG" bs=512 count=32256 status=none
python3 - "$HDD_IMG" <<'PY'
import struct, sys
p = bytearray(512)
p[446:462] = bytes((0, 1, 1, 0, 6, 0, 63, 31)) + struct.pack('<II', 63, 31248)
p[510:512] = b'\x55\xaa'
with open(sys.argv[1], 'r+b') as image:
    image.write(p)
PY
mformat -i "$HDD_IMG@@32256" -t 31 -h 16 -n 63 -H 63 -c 4 ::
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
nasm -f bin "$ROOT/tests/qemu_reboot.asm" -o "$REBOOT_COM"
nasm -f bin "$ROOT/tests/smartdrv_io_probe.asm" -o "$IO_COM"
mcopy -o -i "$BOOT_IMG" "$EXIT_COM" ::QEXIT.COM
mcopy -o -i "$BOOT_IMG" "$REBOOT_COM" ::REBOOT.COM
mcopy -o -i "$BOOT_IMG" "$IO_COM" ::SDIO.COM
printf 'DEVICE=SMARTDRV.EXE 256\r\n' | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'IF EXIST REBOOT.TAG GOTO SECOND\r\n'
    printf 'ECHO pending>REBOOT.TAG\r\n'
    printf 'SMARTDRV C+ /F /Q\r\n'
    printf 'SDIO.COM\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SMARTDRV_REBOOT_IO_FAILED\r\n'
    printf 'REBOOT.COM\r\n'
    printf ':SECOND\r\n'
    printf 'ECHO SMARTDRV_SECOND_BOOT\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

timeout 35 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=ide,index=0,format=raw,file="$HDD_IMG",cache=writethrough \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 -boot a -serial stdio -no-reboot \
    >"$LOG" 2>&1 || true

sector_matches="$(python3 - "$HDD_IMG" <<'PY'
import sys
with open(sys.argv[1], 'rb') as image:
    image.seek((63 + 1000) * 512)
    actual = image.read(512)
expected = b'SMARTDRV_SECTOR_OK' + bytes([0xA5]) * (512 - len(b'SMARTDRV_SECTOR_OK'))
print('yes' if actual == expected else 'no')
PY
)"

if grep -q 'SMARTDRV_SECOND_BOOT' "$LOG" \
    && ! grep -q 'SMARTDRV_REBOOT_IO_FAILED' "$LOG" \
    && [[ "$sector_matches" == yes ]]; then
    echo '  PASS: SMARTDrive flushes dirty fixed-disk data across INT 19h reboot'
    exit 0
fi

echo '  FAIL: SMARTDrive reboot flush contract'
sed -n '1,160p' "$LOG"
exit 1
