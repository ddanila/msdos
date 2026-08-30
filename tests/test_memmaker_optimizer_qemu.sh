#!/bin/bash
set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/memmaker-optimizer.img"
LOG="$OUT/memmaker-optimizer.log"
QEXIT="$OUT/memmaker-optimizer-exit.com"
MEMORY="$OUT/memmaker-optimizer.mem"
SIZES="$OUT/memmaker-optimizer.siz"

for tool in mcopy nasm python3 qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 1; }
done
[[ -f "$BASE" ]] || { echo "missing $BASE; run make deploy" >&2; exit 1; }

cp "$BASE" "$IMAGE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
mcopy -o -i "$IMAGE" "$ROOT/src/CMD/MEMMAKER/MEMMAKER.EXE" ::MEMMAKER.EXE
mcopy -o -i "$IMAGE" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
mcopy -o -i "$IMAGE" "$ROOT/src/MEMM/MEMM/EMM386.EXE" ::EMM386.EXE
mcopy -o -i "$IMAGE" "$QEXIT" ::QEXIT.COM
printf 'DEVICE=A:\\HIMEM.SYS\r\nDEVICE=A:\\EMM386.EXE NOEMS M5\r\nDOS=HIGH,UMB\r\n' \
    | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'MEMMAKER /FINAL /SWAP:A /W:0,0\r\n'
    printf 'QEXIT.COM\r\n'
    printf 'A:\\SIZER.EXE /M:1 /SWAP:A ECHO LARGE\r\n'
    printf 'A:\\SIZER.EXE /M:2 /SWAP:A ECHO MEDIUM1\r\n'
    printf 'A:\\SIZER.EXE /M:3 /SWAP:A ECHO MEDIUM2\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT
python3 - "$MEMORY" "$SIZES" <<'PY'
import struct
import sys

# Eight 16-bit handoff fields: memory snapshots and selection counts.
open(sys.argv[1], "wb").write(struct.pack("<8H", 0, 0, 0, 0, 3, 3, 0, 0))
records = [
    (0x5A53, 1, 20001, 1),
    (0x5A53, 2, 12001, 1),
    (0x5A53, 3, 12001, 1),
]
open(sys.argv[2], "wb").write(b"".join(struct.pack("<4H", *r) for r in records))
PY
mcopy -o -i "$IMAGE" "$MEMORY" ::MEMMAKER.MEM
mcopy -o -i "$IMAGE" "$SIZES" ::MEMMAKER.SIZ

timeout 30 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 </dev/null >"$LOG" 2>&1 || true

autoexec="$(mcopy -i "$IMAGE" ::AUTOEXEC.BAT - 2>/dev/null | tr -d '\r')"
status="$(mcopy -i "$IMAGE" ::MEMMAKER.STS - 2>/dev/null | tr -d '\r')"
grep -q '^ECHO LARGE$' <<<"$autoexec"
! grep -q '^LH ECHO LARGE$' <<<"$autoexec"
grep -q '^LH ECHO MEDIUM1$' <<<"$autoexec"
grep -q '^LH ECHO MEDIUM2$' <<<"$autoexec"
grep -q 'TSRs placed high by measured optimizer: 2, 24000 paragraphs' <<<"$status"
echo '  PASS: MemMaker exact optimizer selects 24000 paragraphs over the 20000-paragraph first fit'
