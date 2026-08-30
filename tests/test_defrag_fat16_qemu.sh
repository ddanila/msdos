#!/bin/bash
set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT="$OUT/defrag-fat16-boot.img"
DISK="$OUT/defrag-fat16.img"
LOG="$OUT/defrag-fat16.log"
QEXIT="$OUT/defrag-fat16-qexit.com"
OFFSET=32256

for tool in nasm mcopy mformat mmd mattrib qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null || { echo "ERROR: missing $tool" >&2; exit 1; }
done
[[ -f "$BASE" ]] || { echo "ERROR: missing $BASE; run make deploy" >&2; exit 1; }

cp "$BASE" "$BOOT"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
mcopy -o -i "$BOOT" "$ROOT/src/CMD/DEFRAG/DEFRAG.EXE" ::DEFRAG.EXE
mcopy -o -i "$BOOT" "$QEXIT" ::QEXIT.COM
dd if=/dev/zero of="$DISK" bs=512 count=32256 status=none
python3 - "$DISK" <<'PY'
import struct, sys
p = bytearray(512)
p[446:462] = bytes((0x80, 1, 1, 0, 6, 0, 63, 31)) + struct.pack('<II', 63, 31248)
p[510:512] = b'\x55\xaa'
open(sys.argv[1], 'r+b').write(p)
PY
mformat -i "$DISK@@$OFFSET" -t 31 -h 16 -n 63 -H 63 -c 4 ::
mmd -i "$DISK@@$OFFSET" ::NEST
python3 - "$OUT" <<'PY'
from pathlib import Path
import sys
out = Path(sys.argv[1])
for name, seed in [('defrag-root.bin', 17), ('defrag-nested.bin', 53),
                   ('defrag-hidden.bin', 91)]:
    out.joinpath(name).write_bytes(bytes((seed + i * 7) & 255 for i in range(7000)))
PY
mcopy -o -i "$DISK@@$OFFSET" "$OUT/defrag-root.bin" ::ROOT.BIN
mcopy -o -i "$DISK@@$OFFSET" "$OUT/defrag-nested.bin" ::NEST/NESTED.BIN
mcopy -o -i "$DISK@@$OFFSET" "$OUT/defrag-hidden.bin" ::HIDDEN.BIN
mattrib -i "$DISK@@$OFFSET" +h ::HIDDEN.BIN

python3 - "$DISK" "$OFFSET" <<'PY'
from pathlib import Path
import struct, sys
path, part = Path(sys.argv[1]), int(sys.argv[2])
disk = bytearray(path.read_bytes())
spc, fats = disk[part + 13], disk[part + 16]
reserved = struct.unpack_from('<H', disk, part + 14)[0]
roots = struct.unpack_from('<H', disk, part + 17)[0]
spf = struct.unpack_from('<H', disk, part + 22)[0]
fat0 = part + reserved * 512
root_sector = reserved + fats * spf
root_bytes = roots * 32
data_sector = root_sector + (root_bytes + 511) // 512
cluster_bytes = spc * 512
def fat_get(c): return struct.unpack_from('<H', disk, fat0 + c * 2)[0]
def fat_set(c, value):
    for copy in range(fats):
        struct.pack_into('<H', disk, fat0 + copy * spf * 512 + c * 2, value)
def coff(c): return part + (data_sector + (c - 2) * spc) * 512
def entries(first=0):
    regions = [(part + root_sector * 512, root_bytes)] if not first else []
    while first and first < 0xfff8:
        regions.append((coff(first), cluster_bytes)); first = fat_get(first)
    for base, size in regions:
        for off in range(base, base + size, 32):
            entry = disk[off:off + 32]
            if not entry[0]: return
            if entry[0] != 0xe5 and entry[11] & 0x0f != 0x0f: yield entry
def find(first, name):
    return next(struct.unpack_from('<H', e, 26)[0] for e in entries(first)
                if e[:11] == name)
def chain(first):
    result = []
    while first < 0xfff8:
        result.append(first); first = fat_get(first)
    return result
nest = find(0, b'NEST       ')
for directory, name, target in [(0, b'ROOT    BIN', 5000),
                                (nest, b'NESTED  BIN', 6000),
                                (0, b'HIDDEN  BIN', 7000)]:
    old = chain(find(directory, name))
    assert len(old) >= 3 and fat_get(target) == 0
    source = old[1]
    disk[coff(target):coff(target) + cluster_bytes] = \
        disk[coff(source):coff(source) + cluster_bytes]
    fat_set(old[0], target); fat_set(target, old[2]); fat_set(source, 0)
path.write_bytes(disk)
PY

{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'IF EXIST A:\\REBOOT.OK GOTO AFTER\r\n'
    printf 'DEFRAG C: /U\r\nIF ERRORLEVEL 1 ECHO DEFRAG_FIRST_FAILED\r\n'
    printf 'DEFRAG C: /U /H\r\nIF ERRORLEVEL 1 ECHO DEFRAG_HIDDEN_FAILED\r\n'
    printf 'ECHO REBOOT>A:\\REBOOT.OK\r\nDEFRAG C: /B /H\r\n'
    printf ':AFTER\r\nECHO DEFRAG_FAT16_REBOOTED\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT

timeout 60 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=ide,index=0,format=raw,file="$DISK",cache=writethrough \
    -boot a -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$LOG" 2>&1 || true
grep -Fq DEFRAG_FAT16_REBOOTED "$LOG"
! grep -Eq 'DEFRAG_(FIRST|HIDDEN)_FAILED' "$LOG"
grep -Fq '3 fragmented, 2 moved.' "$LOG"
grep -Fq '1 fragmented, 1 moved.' "$LOG"
for pair in 'ROOT.BIN:defrag-root.bin' 'NEST/NESTED.BIN:defrag-nested.bin' \
            'HIDDEN.BIN:defrag-hidden.bin'; do
    mcopy -i "$DISK@@$OFFSET" "::${pair%%:*}" - 2>/dev/null | \
        cmp -s - "$OUT/${pair#*:}"
done

python3 - "$DISK" "$OFFSET" <<'PY'
from pathlib import Path
import struct, sys
disk, part = Path(sys.argv[1]).read_bytes(), int(sys.argv[2])
spc, fats = disk[part + 13], disk[part + 16]
reserved = struct.unpack_from('<H', disk, part + 14)[0]
roots = struct.unpack_from('<H', disk, part + 17)[0]
spf = struct.unpack_from('<H', disk, part + 22)[0]
fat = part + reserved * 512
root_sector = reserved + fats * spf
root_size = roots * 32
data_sector = root_sector + (root_size + 511) // 512
cluster_size = spc * 512
def get(c): return struct.unpack_from('<H', disk, fat + c * 2)[0]
def coff(c): return part + (data_sector + (c - 2) * spc) * 512
def entries(first=0):
    regions = [(part + root_sector * 512, root_size)] if not first else []
    while first and first < 0xfff8:
        regions.append((coff(first), cluster_size)); first = get(first)
    for base, size in regions:
        for off in range(base, base + size, 32):
            e = disk[off:off + 32]
            if not e[0]: return
            if e[0] != 0xe5 and e[11] & 0x0f != 0x0f: yield e
def find(first, name):
    return next(struct.unpack_from('<H', e, 26)[0] for e in entries(first)
                if e[:11] == name)
def contiguous(first):
    while get(first) < 0xfff8:
        nxt = get(first)
        if nxt != first + 1: return False
        first = nxt
    return True
nest = find(0, b'NEST       ')
assert contiguous(find(0, b'ROOT    BIN'))
assert contiguous(find(nest, b'NESTED  BIN'))
assert contiguous(find(0, b'HIDDEN  BIN'))
PY
echo '  PASS: FAT16 root, nested, and hidden files are byte-exact and contiguous'
echo '  PASS: /B reboot completed and returned through AUTOEXEC.BAT'
