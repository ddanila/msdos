#!/bin/bash
set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT="$OUT/defrag-errors-boot.img"
PRISTINE="$OUT/defrag-errors-pristine.img"
QEXIT="$OUT/defrag-errors-qexit.com"

for tool in mcopy mformat nasm python3 qemu-system-i386 sha256sum timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 1; }
done
[[ -f "$BASE" ]] || { echo 'run make deploy first' >&2; exit 1; }

cp "$BASE" "$BOOT"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
mcopy -o -i "$BOOT" "$ROOT/src/CMD/DEFRAG/DEFRAG.EXE" ::DEFRAG.EXE
mcopy -o -i "$BOOT" "$QEXIT" ::QEXIT.COM
mformat -C -i "$PRISTINE" -f 1440 ::
printf 'chain validation payload\r\n' | mcopy -o -i "$PRISTINE" - ::CHAIN.TXT

make_case() {
    local kind="$1" expected="$2" mode="${3:-/U}"
    local image="$OUT/defrag-error-$kind.img"
    local log="$OUT/defrag-error-$kind.log"
    if [[ "$kind" == directory-limit ]]; then
        mformat -C -i "$image" -f 1440 ::
    else
        cp "$PRISTINE" "$image"
    fi
    python3 - "$image" "$kind" <<'PY'
from pathlib import Path
import struct
import sys

path, kind = Path(sys.argv[1]), sys.argv[2]
disk = bytearray(path.read_bytes())
bps = struct.unpack_from('<H', disk, 11)[0]
reserved = struct.unpack_from('<H', disk, 14)[0]
fats = disk[16]
root_entries = struct.unpack_from('<H', disk, 17)[0]
total = struct.unpack_from('<H', disk, 19)[0]
spf = struct.unpack_from('<H', disk, 22)[0]
spc = disk[13]
fat_offsets = [(reserved + copy * spf) * bps for copy in range(fats)]
root_start = (reserved + fats * spf) * bps
root_sectors = (root_entries * 32 + bps - 1) // bps
data_start = reserved + fats * spf + root_sectors
clusters = (total - data_start) // spc

def put(base, cluster, value):
    off = base + cluster * 3 // 2
    word = struct.unpack_from('<H', disk, off)[0]
    if cluster & 1:
        word = (word & 0x000f) | ((value & 0xfff) << 4)
    else:
        word = (word & 0xf000) | (value & 0xfff)
    struct.pack_into('<H', disk, off, word)

if kind == 'divergent':
    put(fat_offsets[1], 100, 0xfff)
elif kind == 'lost':
    for base in fat_offsets:
        put(base, 100, 0xfff)
elif kind == 'invalid-chain':
    entry = next(off for off in range(root_start, root_start + root_entries * 32, 32)
                 if disk[off:off + 11] == b'CHAIN   TXT')
    first = struct.unpack_from('<H', disk, entry + 26)[0]
    for base in fat_offsets:
        put(base, first, 1)
elif kind == 'full':
    for base in fat_offsets:
        for cluster in range(2, clusters + 2):
            put(base, cluster, 0xfff)
elif kind == 'invalid-boot':
    struct.pack_into('<H', disk, 11, 0)
elif kind == 'directory-limit':
    first, last = 2, 34
    for base in fat_offsets:
        for cluster in range(first, last):
            put(base, cluster, cluster + 1)
        put(base, last, 0xfff)
    root = root_start
    disk[root:root + 11] = b'BIGDIR     '
    disk[root + 11] = 0x10
    struct.pack_into('<H', disk, root + 26, first)
    entries = []
    dot = bytearray(32); dot[:11] = b'.          '; dot[11] = 0x10
    dotdot = bytearray(32); dotdot[:11] = b'..         '; dotdot[11] = 0x10
    struct.pack_into('<H', dot, 26, first)
    entries.extend((dot, dotdot))
    for number in range(513):
        entry = bytearray(32)
        entry[:11] = ('F%07dTXT' % number).encode('ascii')
        entry[11] = 0x20
        entries.append(entry)
    raw = b''.join(entries) + bytes(32)
    for index, cluster in enumerate(range(first, last + 1)):
        offset = (data_start + (cluster - 2) * spc) * bps
        disk[offset:offset + bps] = raw[index * bps:(index + 1) * bps]
else:
    raise AssertionError(kind)
path.write_bytes(disk)
PY
    local before
    before="$(sha256sum "$image" | awk '{print $1}')"
    {
        printf '@ECHO OFF\r\nCTTY AUX\r\nDEFRAG B: %s\r\n' "$mode"
        printf 'IF ERRORLEVEL %s GOTO TOO_HIGH\r\n' "$((expected + 1))"
        printf 'IF ERRORLEVEL %s GOTO EXPECTED\r\n' "$expected"
        printf ':TOO_HIGH\r\nECHO DEFRAG_ERRORLEVEL_FAIL\r\nGOTO DONE\r\n'
        printf ':EXPECTED\r\nECHO DEFRAG_ERROR_%s_PASS\r\n' "$kind"
        printf ':DONE\r\nQEXIT.COM\r\n'
    } | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT
    timeout 25 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 4 \
        -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
        -drive if=floppy,index=1,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$log" 2>&1 || true
    grep -Fq "DEFRAG_ERROR_${kind}_PASS" "$log"
    ! grep -Fq 'DEFRAG_ERRORLEVEL_FAIL' "$log"
    [[ "$(sha256sum "$image" | awk '{print $1}')" == "$before" ]]
    echo "  PASS: DEFRAG rejects $kind metadata with errorlevel $expected and no writes"
}

make_case divergent 7
make_case lost 7
make_case invalid-chain 7
make_case full 2
make_case invalid-boot 4
make_case directory-limit 9 '/F /SN'
