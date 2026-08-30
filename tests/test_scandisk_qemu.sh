#!/bin/bash

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
BOOT="$OUT/scandisk-boot.img"
TARGET="$OUT/scandisk-target.img"
BEFORE="$OUT/scandisk-before.img"
LOG="$OUT/scandisk-serial.log"
UNDO_BOOT="$OUT/scandisk-undo-boot.img"
UNDO_TARGET="$OUT/scandisk-undo-target.img"
UNDO_REPAIRED="$OUT/scandisk-undo-repaired.img"
UNDO_LOG="$OUT/scandisk-undo.log"
QEXIT="$OUT/scandisk-qexit.com"
PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

[[ -f "$BASE" ]] || { echo "missing $BASE; run make deploy" >&2; exit 1; }
[[ -f "$ROOT/src/CMD/SCANDISK/SCANDISK.EXE" ]] || {
    echo "missing SCANDISK.EXE; run make cmd" >&2
    exit 1
}

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
cp "$BASE" "$BOOT"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
mcopy -o -i "$BOOT" "$ROOT/src/CMD/SCANDISK/SCANDISK.EXE" ::SCANDISK.EXE
mcopy -o -i "$BOOT" "$QEXIT" ::QEXIT.COM

dd if=/dev/zero of="$TARGET" bs=512 count=2880 status=none
mformat -i "$TARGET" -f 1440 ::
printf 'SCANDISK CONTROL PAYLOAD\r\n' | mcopy -o -i "$TARGET" - ::CONTROL.TXT
python3 -c "open('$OUT/scandisk-frag.bin','wb').write(bytes((i & 255 for i in range(1536))))"
mcopy -o -i "$TARGET" "$OUT/scandisk-frag.bin" ::FRAG.BIN
mmd -i "$TARGET" ::BROKEN
printf 'nested payload\r\n' | mcopy -o -i "$TARGET" - ::BROKEN/KEEP.TXT
printf 'duplicate one\r\n' | mcopy -o -i "$TARGET" - ::DUP1.TXT
printf 'duplicate two\r\n' | mcopy -o -i "$TARGET" - ::DUP2.TXT
printf 'invalid name\r\n' | mcopy -o -i "$TARGET" - ::BADNAME.TXT
printf 'lost by invalid cluster\r\n' | mcopy -o -i "$TARGET" - ::BADCLUS.TXT

python3 - "$TARGET" <<'PY'
from pathlib import Path
import struct
import sys

path = Path(sys.argv[1])
disk = bytearray(path.read_bytes())
fat1 = 512
fat2 = 10 * 512

def get_fat12(base, cluster):
    offset = base + cluster * 3 // 2
    word = struct.unpack_from("<H", disk, offset)[0]
    return (word >> 4) & 0xfff if cluster & 1 else word & 0xfff

def set_fat12(base, cluster, value):
    offset = base + cluster * 3 // 2
    word = struct.unpack_from("<H", disk, offset)[0]
    word = ((word & 0x000f) | ((value & 0xfff) << 4)) if cluster & 1 \
        else ((word & 0xf000) | (value & 0xfff))
    struct.pack_into("<H", disk, offset, word)

for cluster in (100, 101, 102):
    assert get_fat12(fat1, cluster) == 0
for base in (fat1, fat2):
    set_fat12(base, 100, 101)
    set_fat12(base, 101, 102)
    set_fat12(base, 102, 0xfff)

# Make one otherwise-unused FAT2 entry disagree with FAT1. Autofix must restore
# the secondary copy without disturbing the orphan payload.
set_fat12(fat2, 200, 0xfff)

# Relocate the middle cluster of FRAG.BIN so /FRAGMENT must observe three
# physical extents without changing any file byte.
root = 19 * 512
entry = next(root + off for off in range(0, 224 * 32, 32)
             if disk[root + off:root + off + 11] == b'FRAG    BIN')
c1 = struct.unpack_from('<H', disk, entry + 26)[0]
c2 = get_fat12(fat1, c1)
c3 = get_fat12(fat1, c2)
assert c3 >= 2 and get_fat12(fat1, c3) >= 0xff8
target = 300
assert get_fat12(fat1, target) == 0
data_offset = 33 * 512
disk[data_offset + (target - 2) * 512:data_offset + (target - 1) * 512] = \
    disk[data_offset + (c2 - 2) * 512:data_offset + (c2 - 1) * 512]
for base in (fat1, fat2):
    set_fat12(base, c1, target)
    set_fat12(base, target, c3)
    set_fat12(base, c2, 0)

broken_entry = next(root + off for off in range(0, 224 * 32, 32)
                    if disk[root + off:root + off + 11] == b'BROKEN     ')
broken_cluster = struct.unpack_from('<H', disk, broken_entry + 26)[0]
struct.pack_into('<I', disk, broken_entry + 28, 123)
broken_sector = data_offset + (broken_cluster - 2) * 512
struct.pack_into('<H', disk, broken_sector + 26, 999)
struct.pack_into('<H', disk, broken_sector + 32 + 26, 999)
# A volume label is legal only in the root. Put one in the first unused
# subdirectory slot; ScanDisk should remove the metadata-only entry.
label = broken_sector + 32 * 3
disk[label:label + 11] = b'BAD LABEL  '
disk[label + 11] = 0x08

def root_entry(name):
    return next(root + off for off in range(0, 224 * 32, 32)
                if disk[root + off:root + off + 11] == name)

control_entry = root_entry(b'CONTROL TXT')
disk[control_entry + 11] |= 0xc0
dup2_entry = root_entry(b'DUP2    TXT')
disk[dup2_entry:dup2_entry + 11] = b'DUP1    TXT'
dup1_entry = root_entry(b'DUP1    TXT')
struct.pack_into('<HH', disk, dup1_entry + 22, 0xffff, 0x01ff)
badname_entry = root_entry(b'BADNAME TXT')
disk[badname_entry] = ord('*')
badclus_entry = root_entry(b'BADCLUS TXT')
struct.pack_into('<H', disk, badclus_entry + 26, 0x0b50)

data = 33 * 512
for cluster in (100, 101, 102):
    start = data + (cluster - 2) * 512
    disk[start:start + 512] = bytes((cluster + i) & 0xff for i in range(512))
path.write_bytes(disk)
PY

cp "$TARGET" "$BEFORE"
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'SCANDISK /FRAGMENT B:\\*.BIN\r\n'
    printf 'IF ERRORLEVEL 1 ECHO FRAGMENT_FAILED\r\n'
    printf 'SCANDISK B: /CHECKONLY /NOSUMMARY\r\n'
    printf 'IF ERRORLEVEL 255 ECHO CHECKONLY_FOUND_ERRORS\r\n'
    printf 'SCANDISK B: /AUTOFIX /NOSUMMARY\r\n'
    printf 'IF ERRORLEVEL 255 ECHO AUTOFIX_FAILED\r\n'
    printf 'IF ERRORLEVEL 254 ECHO AUTOFIX_REPAIRED\r\n'
    printf 'IF EXIST B:\\FILE0000.CHK ECHO RECOVERED_FILE_PRESENT\r\n'
    printf 'SCANDISK B: /CHECKONLY\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESCAN_FAILED\r\n'
    printf 'SCANDISK B: /CHECKONLY /SURFACE /NOSUMMARY\r\n'
    printf 'IF ERRORLEVEL 1 ECHO SURFACE_FAILED\r\n'
    printf 'ECHO SCANDISK_DONE\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BOOT" - ::AUTOEXEC.BAT

timeout 45 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >"$LOG" 2>&1 || true

grep -q 'CHECKONLY_FOUND_ERRORS' "$LOG" &&
    ok "/CHECKONLY detects corruption and returns failure" ||
    fail "/CHECKONLY did not report corruption through its status"
if grep -q 'B:\\FRAG.BIN occupies 3 cluster(s) in 3 fragment(s)' "$LOG" &&
   ! grep -q 'FRAGMENT_FAILED' "$LOG"; then
    ok "/FRAGMENT follows the named file's physical FAT chain"
else
    fail "/FRAGMENT did not report the injected three-extent chain"
fi
grep -q 'file allocation table copies differ' "$LOG" &&
    ok "mismatched FAT mirrors are detected" ||
    fail "FAT mirror mismatch was not diagnosed"
if grep -q 'invalid \. entry' "$LOG" &&
   grep -q 'invalid \.\. entry' "$LOG" &&
   grep -q 'directory entry has a nonzero file size' "$LOG"; then
    ok "directory metadata validation detects dot-parent and size corruption"
else
    fail "directory metadata corruption was not fully diagnosed"
fi
if grep -q 'invalid or duplicate name' "$LOG" &&
   grep -q 'invalid attributes' "$LOG" &&
   grep -q 'invalid date or time' "$LOG"; then
    ok "invalid names, duplicates, attributes, and timestamps are detected"
else
    fail "directory name, attribute, or timestamp corruption was not diagnosed"
fi
if grep -q 'subdirectory contains a volume-label entry' "$LOG" &&
   grep -q 'invalid starting cluster' "$LOG"; then
    ok "misplaced labels and invalid starting clusters are detected"
else
    fail "directory structural corruption was not fully diagnosed"
fi
grep -q 'RECOVERED_FILE_PRESENT' "$LOG" &&
    ok "/AUTOFIX converts the orphan chain to FILE0000.CHK" ||
    fail "lost chain was not recovered"
if grep -Eq 'AUTOFIX_FAILED|RESCAN_FAILED|SURFACE_FAILED' "$LOG" ||
   ! grep -q 'AUTOFIX_REPAIRED' "$LOG"; then
    fail "repair or clean rescan returned failure"
else
    ok "repair succeeds and a second /CHECKONLY scan is clean"
fi
grep -q 'SURFACE_FAILED' "$LOG" ||
    ok "/SURFACE completes non-destructive read/write verification of free space"

expected="$(python3 - <<'PY'
import hashlib
data = b''.join(bytes((cluster + i) & 0xff for i in range(512))
                for cluster in (100, 101, 102))
print(hashlib.sha256(data).hexdigest())
PY
)"
actual0="$(mcopy -i "$TARGET" ::FILE0000.CHK - 2>/dev/null | sha256sum | awk '{print $1}')"
actual1="$(mcopy -i "$TARGET" ::FILE0001.CHK - 2>/dev/null | sha256sum | awk '{print $1}')"
[[ "$actual0" == "$expected" || "$actual1" == "$expected" ]] &&
    ok "recovered chain payload is byte-exact" ||
    fail "recovered chain payload differs"

dup_payload="$(mcopy -i "$TARGET" ::FOUND000.CHK - 2>/dev/null | tr -d '\r\n')"
bad_payload="$(mcopy -i "$TARGET" ::FOUND001.CHK - 2>/dev/null | tr -d '\r\n')"
if [[ "$dup_payload" == 'duplicate two' && "$bad_payload" == 'invalid name' ]]; then
    ok "name repairs preserve both formerly ambiguous file payloads"
else
    fail "name repairs did not preserve the renamed file payloads"
fi
if (mcopy -i "$TARGET" ::FILE0000.CHK - 2>/dev/null |
        strings | grep -qx 'lost by invalid cluster') ||
   (mcopy -i "$TARGET" ::FILE0001.CHK - 2>/dev/null |
        strings | grep -qx 'lost by invalid cluster'); then
    ok "the chain orphaned by an invalid start is recovered byte-exactly"
else
    fail "invalid-start repair did not recover the original chain"
fi

control="$(mcopy -i "$TARGET" ::CONTROL.TXT - 2>/dev/null | tr -d '\r\n')"
[[ "$control" == 'SCANDISK CONTROL PAYLOAD' ]] &&
    ok "referenced file data is preserved" ||
    fail "referenced file data changed"

python3 - "$TARGET" <<'PY' && ok "all FAT copies match after repair" || fail "FAT copies still differ"
from pathlib import Path
import struct
import sys
disk = Path(sys.argv[1]).read_bytes()
reserved = struct.unpack_from('<H', disk, 14)[0]
fats = disk[16]
size = struct.unpack_from('<H', disk, 22)[0] * 512
first = disk[reserved * 512:reserved * 512 + size]
assert all(disk[(reserved + n * size // 512) * 512:
                    (reserved + n * size // 512) * 512 + size] == first
           for n in range(1, fats))
PY

python3 - "$TARGET" <<'PY' && ok "directory dot entries and size were repaired exactly" || fail "directory metadata repair is incomplete"
from pathlib import Path
import struct, sys
disk = Path(sys.argv[1]).read_bytes()
root = 19 * 512
entry = next(root + off for off in range(0, 224 * 32, 32)
             if disk[root + off:root + off + 11] == b'BROKEN     ')
cluster = struct.unpack_from('<H', disk, entry + 26)[0]
sector = (33 + cluster - 2) * 512
assert struct.unpack_from('<I', disk, entry + 28)[0] == 0
assert disk[sector:sector + 11] == b'.          '
assert struct.unpack_from('<H', disk, sector + 26)[0] == cluster
assert disk[sector + 32:sector + 43] == b'..         '
assert struct.unpack_from('<H', disk, sector + 32 + 26)[0] == 0
assert disk[sector + 32 * 3] == 0xe5

dup = next(root + off for off in range(0, 224 * 32, 32)
           if disk[root + off:root + off + 11] == b'DUP1    TXT')
time, date = struct.unpack_from('<HH', disk, dup + 22)
month, day = (date >> 5) & 15, date & 31
assert (time >> 11) <= 23 and ((time >> 5) & 63) <= 59
assert 1 <= month <= 12 and 1 <= day <= 31

badclus = next(root + off for off in range(0, 224 * 32, 32)
               if disk[root + off:root + off + 11] == b'BADCLUS TXT')
assert struct.unpack_from('<H', disk, badclus + 26)[0] == 0
assert struct.unpack_from('<I', disk, badclus + 28)[0] == 0
PY

grep -q 'SCANDISK_DONE' "$LOG" && ok "DOS batch completed" || {
    fail "DOS batch did not complete"
    tail -40 "$LOG"
}
repair_log="$(mcopy -i "$BOOT" ::SCANDISK.LOG - 2>/dev/null | tr -d '\r' || true)"
if grep -q 'Drive B:.*problem(s).*repair(s)' <<<"$repair_log"; then
    ok "logical checks and repairs append SCANDISK.LOG"
else
    fail "SCANDISK.LOG lacks the drive repair summary"
fi

echo "Testing Undo-disk creation and reverse-order restoration..."
cp "$BASE" "$UNDO_BOOT"
cp "$BEFORE" "$UNDO_TARGET"
mcopy -o -i "$UNDO_BOOT" "$ROOT/src/CMD/SCANDISK/SCANDISK.EXE" ::SCANDISK.EXE
mcopy -o -i "$UNDO_BOOT" "$QEXIT" ::QEXIT.COM
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'SCANDISK B: /AUTOFIX\r\n'
    printf 'IF ERRORLEVEL 255 ECHO UNDO_REPAIR_FAILED\r\n'
    printf 'ECHO UNDO_CREATED\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$UNDO_BOOT" - ::AUTOEXEC.BAT
printf 'Y\r\r' | timeout 45 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$UNDO_BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$UNDO_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    >"$UNDO_LOG" 2>&1 || true

if mdir -i "$UNDO_BOOT" ::SCANDISK.UND >/dev/null 2>&1 &&
   grep -q 'UNDO_CREATED' "$UNDO_LOG" &&
   ! grep -q 'UNDO_REPAIR_FAILED' "$UNDO_LOG"; then
    ok "automatic repair creates a separate Undo disk record"
else
    fail "Undo disk was not created during repair"
fi

cp "$UNDO_TARGET" "$UNDO_REPAIRED"
printf 'changed after repair\r\n' | mcopy -o -i "$UNDO_TARGET" - ::LATER.TXT
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'SCANDISK /UNDO A:\r\n'
    printf 'IF ERRORLEVEL 2 ECHO STALE_UNDO_REFUSED\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$UNDO_BOOT" - ::AUTOEXEC.BAT
timeout 45 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$UNDO_BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$UNDO_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >>"$UNDO_LOG" 2>&1 || true
if grep -q 'STALE_UNDO_REFUSED' "$UNDO_LOG" &&
   mdir -i "$UNDO_TARGET" ::LATER.TXT >/dev/null 2>&1; then
    ok "/UNDO refuses stale metadata after the target changes"
else
    fail "/UNDO accepted or modified a stale target"
fi

cp "$UNDO_REPAIRED" "$UNDO_TARGET"

{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'SCANDISK /UNDO A:\r\n'
    printf 'IF ERRORLEVEL 1 ECHO UNDO_RESTORE_FAILED\r\n'
    printf 'ECHO UNDO_RESTORED\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$UNDO_BOOT" - ::AUTOEXEC.BAT
timeout 45 qemu-system-i386 -display none \
    -drive if=floppy,index=0,format=raw,file="$UNDO_BOOT",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$UNDO_TARGET",cache=writethrough \
    -boot a -m 4 -serial stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    </dev/null >>"$UNDO_LOG" 2>&1 || true

before_hash="$(sha256sum "$BEFORE" | awk '{print $1}')"
undo_hash="$(sha256sum "$UNDO_TARGET" | awk '{print $1}')"
if [[ "$undo_hash" == "$before_hash" ]] &&
   grep -q 'UNDO_RESTORED' "$UNDO_LOG" &&
   ! grep -q 'UNDO_RESTORE_FAILED' "$UNDO_LOG"; then
    ok "/UNDO restores every changed target-sector byte"
else
    fail "/UNDO did not restore the original corrupt volume image"
    tail -40 "$UNDO_LOG"
fi

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
