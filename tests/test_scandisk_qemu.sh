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
data = 33 * 512
for cluster in (100, 101, 102):
    start = data + (cluster - 2) * 512
    disk[start:start + 512] = bytes((cluster + i) & 0xff for i in range(512))
path.write_bytes(disk)
PY

cp "$TARGET" "$BEFORE"
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'SCANDISK B: /CHECKONLY /NOSUMMARY\r\n'
    printf 'IF ERRORLEVEL 255 ECHO CHECKONLY_FOUND_ERRORS\r\n'
    printf 'SCANDISK B: /AUTOFIX /NOSUMMARY\r\n'
    printf 'IF ERRORLEVEL 255 ECHO AUTOFIX_FAILED\r\n'
    printf 'IF ERRORLEVEL 254 ECHO AUTOFIX_REPAIRED\r\n'
    printf 'IF EXIST B:\\FILE0000.CHK ECHO RECOVERED_FILE_PRESENT\r\n'
    printf 'SCANDISK B: /CHECKONLY\r\n'
    printf 'IF ERRORLEVEL 1 ECHO RESCAN_FAILED\r\n'
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
grep -q 'file allocation table copies differ' "$LOG" &&
    ok "mismatched FAT mirrors are detected" ||
    fail "FAT mirror mismatch was not diagnosed"
grep -q 'RECOVERED_FILE_PRESENT' "$LOG" &&
    ok "/AUTOFIX converts the orphan chain to FILE0000.CHK" ||
    fail "lost chain was not recovered"
if grep -Eq 'AUTOFIX_FAILED|RESCAN_FAILED' "$LOG" ||
   ! grep -q 'AUTOFIX_REPAIRED' "$LOG"; then
    fail "repair or clean rescan returned failure"
else
    ok "repair succeeds and a second /CHECKONLY scan is clean"
fi

expected="$(python3 - <<'PY'
import hashlib
data = b''.join(bytes((cluster + i) & 0xff for i in range(512))
                for cluster in (100, 101, 102))
print(hashlib.sha256(data).hexdigest())
PY
)"
actual="$(mcopy -i "$TARGET" ::FILE0000.CHK - 2>/dev/null | sha256sum | awk '{print $1}')"
[[ "$actual" == "$expected" ]] &&
    ok "recovered chain payload is byte-exact" ||
    fail "recovered chain payload differs"

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
