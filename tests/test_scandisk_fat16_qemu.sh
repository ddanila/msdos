#!/bin/bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT="$OUT/scandisk-fat16-boot.img"
DISK="$OUT/scandisk-fat16.img"
LOG="$OUT/scandisk-fat16.log"
QEXIT="$OUT/scandisk-fat16-qexit.com"
OFFSET=32256
PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

[[ -f "$BASE" ]] || { echo "missing $BASE; run make deploy" >&2; exit 1; }
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
cp "$BASE" "$BOOT"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
mcopy -o -i "$BOOT" "$ROOT/src/CMD/SCANDISK/SCANDISK.EXE" ::SCANDISK.EXE
mcopy -o -i "$BOOT" "$QEXIT" ::QEXIT.COM

dd if=/dev/zero of="$DISK" bs=512 count=32256 status=none
python3 - "$DISK" <<'PY'
import struct
import sys
p = bytearray(512)
p[446:462] = bytes((0x80, 1, 1, 0, 6, 0, 63, 31)) + struct.pack('<II', 63, 31248)
p[510:512] = b'\x55\xaa'
with open(sys.argv[1], 'r+b') as f:
    f.write(p)
PY
mformat -i "$DISK@@$OFFSET" -t 31 -h 16 -n 63 -H 63 -c 4 ::
printf 'FAT16 CONTROL\r\n' | mcopy -o -i "$DISK@@$OFFSET" - ::CONTROL.TXT

python3 - "$DISK" "$OFFSET" <<'PY'
from pathlib import Path
import struct
import sys

path = Path(sys.argv[1])
part = int(sys.argv[2])
disk = bytearray(path.read_bytes())
reserved = struct.unpack_from('<H', disk, part + 14)[0]
fat_count = disk[part + 16]
fat_sectors = struct.unpack_from('<H', disk, part + 22)[0]
root_entries = struct.unpack_from('<H', disk, part + 17)[0]
spc = disk[part + 13]
fat1 = part + reserved * 512

def get(base, cluster):
    return struct.unpack_from('<H', disk, base + cluster * 2)[0]

def set_entry(base, cluster, value):
    struct.pack_into('<H', disk, base + cluster * 2, value)

for cluster in (300, 301):
    assert get(fat1, cluster) == 0
for copy in range(fat_count):
    base = fat1 + copy * fat_sectors * 512
    set_entry(base, 300, 301)
    set_entry(base, 301, 0xffff)
set_entry(fat1 + fat_sectors * 512, 500, 0xffff)

root_sectors = (root_entries * 32 + 511) // 512
data_sector = reserved + fat_count * fat_sectors + root_sectors
for cluster in (300, 301):
    start = part + (data_sector + (cluster - 2) * spc) * 512
    size = spc * 512
    disk[start:start + size] = bytes((cluster + i) & 0xff for i in range(size))
path.write_bytes(disk)
PY

{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'SCANDISK C: /CHECKONLY /NOSUMMARY\r\n'
    printf 'IF ERRORLEVEL 255 ECHO FAT16_ERRORS_FOUND\r\n'
    printf 'SCANDISK C: /AUTOFIX /NOSUMMARY\r\n'
    printf 'IF ERRORLEVEL 255 ECHO FAT16_REPAIR_FAILED\r\n'
    printf 'IF ERRORLEVEL 254 ECHO FAT16_REPAIRED\r\n'
    printf 'SCANDISK C: /CHECKONLY\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FAT16_RESCAN_FAILED\r\n'
    printf 'IF EXIST C:\\FILE0000.CHK ECHO FAT16_FILE_PRESENT\r\n'
    printf 'ECHO FAT16_DONE\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT

timeout 45 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=ide,index=0,format=raw,file="$DISK",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$LOG" 2>&1 || true

if grep -q 'FAT16_ERRORS_FOUND' "$LOG" && grep -q 'FAT16_REPAIRED' "$LOG" &&
   ! grep -Eq 'FAT16_REPAIR_FAILED|FAT16_RESCAN_FAILED' "$LOG"; then
    ok "FAT16 detection, automatic repair, and clean rescan complete"
else
    fail "FAT16 runtime contract"
    tail -50 "$LOG"
fi

control="$(mcopy -i "$DISK@@$OFFSET" ::CONTROL.TXT - 2>/dev/null | tr -d '\r\n')"
[[ "$control" == 'FAT16 CONTROL' ]] && ok "FAT16 referenced data is preserved" || fail "FAT16 control data changed"

expected="$(python3 - <<'PY'
import hashlib
print(hashlib.sha256(b''.join(bytes((cluster + i) & 0xff for i in range(2048))
                               for cluster in (300, 301))).hexdigest())
PY
)"
actual="$(mcopy -i "$DISK@@$OFFSET" ::FILE0000.CHK - 2>/dev/null | sha256sum | awk '{print $1}')"
[[ "$actual" == "$expected" ]] && ok "FAT16 orphan payload is byte-exact" || fail "FAT16 recovered payload differs"

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
