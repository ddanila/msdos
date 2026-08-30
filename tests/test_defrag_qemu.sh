#!/bin/bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT="$OUT/defrag-boot.img"
TARGET="$OUT/defrag-target.img"
INTERRUPT_TARGET="$OUT/defrag-interrupt-target.img"
INTERRUPT_BOOT="$OUT/defrag-interrupt-boot.img"
INTERRUPT_LOG="$OUT/defrag-interrupt.log"
LOG="$OUT/defrag.log"
QEXIT="$OUT/defrag-qexit.com"
PAYLOAD="$OUT/defrag-payload.bin"
SINGLE="$OUT/defrag-single.bin"
PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

[[ -f "$BASE" ]] || { echo "missing $BASE; run make deploy" >&2; exit 1; }
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
cp "$BASE" "$BOOT"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
mcopy -o -i "$BOOT" "$ROOT/src/CMD/DEFRAG/DEFRAG.EXE" ::DEFRAG.EXE
mcopy -o -i "$BOOT" "$QEXIT" ::QEXIT.COM
dd if=/dev/zero of="$TARGET" bs=512 count=2880 status=none
mformat -i "$TARGET" -f 1440 ::
python3 - "$PAYLOAD" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(bytes((i * 37 + 11) & 0xff for i in range(1536)))
PY
mcopy -o -i "$TARGET" "$PAYLOAD" ::FRAGMENT.BIN
printf 'single-cluster-compaction-payload\r\n' >"$SINGLE"
mcopy -o -i "$TARGET" "$SINGLE" ::SINGLE.BIN
printf 'zeta\r\n' | mcopy -o -i "$TARGET" - ::ZETA.TXT
printf 'alpha\r\n' | mcopy -o -i "$TARGET" - ::ALPHA.TXT

python3 - "$TARGET" <<'PY'
from pathlib import Path
import struct
import sys

path = Path(sys.argv[1])
disk = bytearray(path.read_bytes())
fat_offsets = (512, 10 * 512)
root = 19 * 512
data = 33 * 512

def get(base, cluster):
    off = base + cluster * 3 // 2
    word = struct.unpack_from('<H', disk, off)[0]
    return (word >> 4) & 0xfff if cluster & 1 else word & 0xfff

def put(base, cluster, value):
    off = base + cluster * 3 // 2
    word = struct.unpack_from('<H', disk, off)[0]
    word = ((word & 0x000f) | ((value & 0xfff) << 4)) if cluster & 1 \
        else ((word & 0xf000) | (value & 0xfff))
    struct.pack_into('<H', disk, off, word)

entry = None
single_entry = None
for off in range(root, root + 14 * 512, 32):
    if disk[off:off + 11] == b'FRAGMENTBIN':
        entry = off
    if disk[off:off + 11] == b'SINGLE  BIN':
        single_entry = off
assert entry is not None and single_entry is not None
old = struct.unpack_from('<H', disk, entry + 26)[0]
chain = []
current = old
while current < 0xff8:
    chain.append(current)
    current = get(fat_offsets[0], current)
assert len(chain) == 3
for target, source in zip((100, 200, 300), chain):
    src = data + (source - 2) * 512
    dst = data + (target - 2) * 512
    disk[dst:dst + 512] = disk[src:src + 512]
for base in fat_offsets:
    for cluster in chain:
        put(base, cluster, 0)
    put(base, 100, 200)
    put(base, 200, 300)
    put(base, 300, 0xfff)
single_old = struct.unpack_from('<H', disk, single_entry + 26)[0]
src = data + (single_old - 2) * 512
dst = data + (500 - 2) * 512
disk[dst:dst + 512] = disk[src:src + 512]
for base in fat_offsets:
    put(base, single_old, 0)
    put(base, 500, 0xfff)
struct.pack_into('<H', disk, entry + 26, 100)
struct.pack_into('<H', disk, single_entry + 26, 500)
path.write_bytes(disk)
PY
cp "$TARGET" "$INTERRUPT_TARGET"

{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'DEFRAG B: /U\r\n'
    printf 'IF ERRORLEVEL 1 ECHO DEFRAG_FAILED\r\n'
    printf 'DEFRAG B: /F /SN\r\n'
    printf 'IF ERRORLEVEL 1 ECHO DEFRAG_FULL_FAILED\r\n'
    printf 'DEFRAG B: /F /SN /B /SKIPHIGH /LCD /H /U\r\n'
    printf 'IF ERRORLEVEL 4 ECHO DEFRAG_CONFLICT_REJECTED\r\n'
    printf 'DEFRAG B: /BW /G0 /U\r\n'
    printf 'IF ERRORLEVEL 4 ECHO DEFRAG_DISPLAY_CONFLICT_REJECTED\r\n'
    printf 'ECHO DEFRAG_DONE\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT

timeout 45 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$LOG" 2>&1 || true

if grep -q 'DEFRAG_DONE' "$LOG" && ! grep -Eq 'DEFRAG_FAILED|DEFRAG_FULL_FAILED' "$LOG" &&
   grep -q '1 fragmented, 1 moved' "$LOG" &&
   grep -q 'DEFRAG_CONFLICT_REJECTED' "$LOG" &&
   grep -q 'DEFRAG_DISPLAY_CONFLICT_REJECTED' "$LOG"; then
    ok "/U relocates the fragmented FAT12 file"
else
    fail "DEFRAG /U runtime"
    tail -50 "$LOG"
fi

expected="$(sha256sum "$PAYLOAD" | awk '{print $1}')"
actual="$(mcopy -i "$TARGET" ::FRAGMENT.BIN - 2>/dev/null | sha256sum | awk '{print $1}')"
[[ "$actual" == "$expected" ]] && ok "relocated payload is byte-exact" || fail "relocated payload differs"
single_expected="$(sha256sum "$SINGLE" | awk '{print $1}')"
single_actual="$(mcopy -i "$TARGET" ::SINGLE.BIN - 2>/dev/null | sha256sum | awk '{print $1}')"
[[ "$single_actual" == "$single_expected" ]] && ok "/F preserves compacted singleton data" || fail "/F changed singleton data"

python3 - "$TARGET" <<'PY' && ok "chains are contiguous, free space is packed, and /SN order is physical" || fail "final FAT or directory order is not optimized"
from pathlib import Path
import struct
import sys
disk = Path(sys.argv[1]).read_bytes()
root = 19 * 512
fat = 512
for off in range(root, root + 14 * 512, 32):
    if disk[off:off + 11] == b'FRAGMENTBIN':
        current = struct.unpack_from('<H', disk, off + 26)[0]
        break
else:
    raise AssertionError('directory entry missing')
chain = []
while current < 0xff8:
    chain.append(current)
    pos = fat + current * 3 // 2
    word = struct.unpack_from('<H', disk, pos)[0]
    current = ((word >> 4) & 0xfff) if current & 1 else (word & 0xfff)
assert len(chain) == 3
assert chain == list(range(chain[0], chain[0] + 3)), chain
for off in range(root, root + 14 * 512, 32):
    if disk[off:off + 11] == b'SINGLE  BIN':
        single = struct.unpack_from('<H', disk, off + 26)[0]
        break
else:
    raise AssertionError('single entry missing')
assert single == 7, (chain, single)
def fat_value(cluster):
    pos = fat + cluster * 3 // 2
    word = struct.unpack_from('<H', disk, pos)[0]
    return ((word >> 4) & 0xfff) if cluster & 1 else (word & 0xfff)
assert all(fat_value(cluster) for cluster in range(2, 8))
assert fat_value(8) == 0
names = []
for off in range(root, root + 14 * 512, 32):
    if disk[off] == 0:
        break
    if disk[off] == 0xe5 or disk[off + 11] & 0x08:
        continue
    names.append(disk[off:off + 11])
assert names == sorted(names, key=lambda value: value[:8]), names
PY

cp "$BASE" "$INTERRUPT_BOOT"
mcopy -o -i "$INTERRUPT_BOOT" "$ROOT/src/CMD/DEFRAG/DEFRAG.EXE" ::DEFRAG.EXE
mcopy -o -i "$INTERRUPT_BOOT" "$ROOT/src/CMD/SCANDISK/SCANDISK.EXE" ::SCANDISK.EXE
mcopy -o -i "$INTERRUPT_BOOT" "$QEXIT" ::QEXIT.COM
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'SET DEFRAG_FAILSTEP=2\r\n'
    printf 'DEFRAG B: /U\r\n'
    printf 'IF ERRORLEVEL 3 ECHO DEFRAG_INTERRUPTED\r\n'
    printf 'SET DEFRAG_FAILSTEP=\r\n'
    printf 'SCANDISK B: /CHECKONLY /NOSUMMARY\r\n'
    printf 'IF ERRORLEVEL 255 ECHO INTERRUPT_ORPHAN_FOUND\r\n'
    printf 'SCANDISK B: /AUTOFIX /NOSAVE /NOSUMMARY\r\n'
    printf 'IF ERRORLEVEL 254 ECHO INTERRUPT_RECOVERED\r\n'
    printf 'SCANDISK B: /CHECKONLY /NOSUMMARY\r\n'
    printf 'IF ERRORLEVEL 1 ECHO INTERRUPT_RESCAN_FAILED\r\n'
    printf 'ECHO INTERRUPT_DONE\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$INTERRUPT_BOOT" - ::AUTOEXEC.BAT
timeout 45 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$INTERRUPT_BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$INTERRUPT_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$INTERRUPT_LOG" 2>&1 || true
interrupt_payload="$(mcopy -i "$INTERRUPT_TARGET" ::FRAGMENT.BIN - 2>/dev/null | sha256sum | awk '{print $1}')"
if [[ "$interrupt_payload" == "$expected" ]] &&
   grep -q 'DEFRAG_INTERRUPTED' "$INTERRUPT_LOG" &&
   grep -q 'INTERRUPT_ORPHAN_FOUND' "$INTERRUPT_LOG" &&
   grep -q 'INTERRUPT_RECOVERED' "$INTERRUPT_LOG" &&
   ! grep -q 'INTERRUPT_RESCAN_FAILED' "$INTERRUPT_LOG"; then
    ok "interruption leaves referenced data exact and only a recoverable orphan"
else
    fail "transaction-boundary interruption was not safely recoverable"
    tail -60 "$INTERRUPT_LOG"
fi

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
