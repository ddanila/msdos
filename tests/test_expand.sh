#!/bin/bash

set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
EXPAND="${EXPAND_PROGRAM:-$ROOT/src/CMD/EXPAND/EXPAND.EXE}"
KVIKDOS="$ROOT/kvikdos/kvikdos-soft"
WORK="$(mktemp -d "$OUT/expand-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

for file in "$EXPAND" "$KVIKDOS"; do
    [[ -f "$file" ]] || { echo "ERROR: missing $file"; exit 1; }
done
cp "$EXPAND" "$WORK/EXPAND.EXE"
mkdir "$WORK/OUTDIR"

python3 - "$WORK" <<'PY'
import os, struct, sys

root = sys.argv[1]

def literal(name, restored, payload):
    encoded = bytearray(b'SZDD\x88\xf0\x27\x33\x41')
    encoded += restored.encode('ascii') + struct.pack('<I', len(payload))
    for offset in range(0, len(payload), 8):
        encoded.append(0xff)
        encoded += payload[offset:offset + 8]
    with open(os.path.join(root, name), 'wb') as f:
        f.write(encoded)

one = (b'one compressed payload\r\n' * 37) + bytes(range(256))
two = b'two payload\x00with binary bytes\r\n'
long_data = (bytes(range(256)) * 300) + b'long-file-end'
literal('ONE.TX_', 'T', one)
literal('TWO.BI_', 'N', two)
literal('LONG.DA_', 'T', long_data)
with open(os.path.join(root, 'ONE.EXP'), 'wb') as f: f.write(one)
with open(os.path.join(root, 'TWO.EXP'), 'wb') as f: f.write(two)
with open(os.path.join(root, 'LONG.EXP'), 'wb') as f: f.write(long_data)

# One back-reference: the initial 4 KiB dictionary contains spaces.
with open(os.path.join(root, 'MATCH.TX_'), 'wb') as f:
    f.write(b'SZDD\x88\xf0\x27\x33\x41T' + struct.pack('<I', 18) + bytes((0, 0, 15)))
with open(os.path.join(root, 'MATCH.EXP'), 'wb') as f: f.write(b' ' * 18)

with open(os.path.join(root, 'BAD.TX_'), 'wb') as f: f.write(b'not an SZDD stream')
with open(os.path.join(root, 'SHORT.TX_'), 'wb') as f:
    f.write(b'SZDD\x88\xf0\x27\x33\x41T' + struct.pack('<I', 100) + b'\xffshort')
PY

PASS=0
FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

run_expand() {
    "$KVIKDOS" --dos-version=5 --mount=c:"$WORK"/ --drive=c \
        --prog='C:\EXPAND.EXE' "$WORK/EXPAND.EXE" "$@" 2>&1
}

echo "=== EXPAND DOS 5 tests ==="

output="$(run_expand /? || true)"
if grep -q 'Usage: EXPAND source' <<<"$output"; then
    ok "EXPAND /? reports the positional DOS 5 syntax"
else
    fail "EXPAND /? help"
fi

run_expand ONE.TX_ RESULT.TXT >/dev/null
if cmp -s "$WORK/ONE.EXP" "$WORK/RESULT.TXT"; then
    ok "single-source expansion to an explicit filename is byte-exact"
else
    fail "single-source explicit destination"
fi

run_expand LONG.DA_ LONG.OUT >/dev/null
if cmp -s "$WORK/LONG.EXP" "$WORK/LONG.OUT"; then
    ok "streaming expansion handles output larger than 64 KiB"
else
    fail "large streaming expansion"
fi

run_expand MATCH.TX_ MATCH.OUT >/dev/null
if cmp -s "$WORK/MATCH.EXP" "$WORK/MATCH.OUT"; then
    ok "SZDD dictionary back-references decode exactly"
else
    fail "SZDD back-reference decoding"
fi

run_expand ONE.TX_ TWO.BI_ 'OUTDIR\' >/dev/null
if cmp -s "$WORK/ONE.EXP" "$WORK/OUTDIR/ONE.TXT" \
    && cmp -s "$WORK/TWO.EXP" "$WORK/OUTDIR/TWO.BIN"; then
    ok "multiple sources expand into a directory with restored extensions"
else
    fail "multi-source directory expansion or restored names"
fi

output="$(run_expand 'ONE.*' WILD.OUT || true)"
if grep -q 'Wildcards are not allowed' <<<"$output" && [[ ! -e "$WORK/WILD.OUT" ]]; then
    ok "wildcards are rejected without creating output"
else
    fail "wildcard rejection"
fi

output="$(run_expand ONE.TX_ TWO.BI_ NOTDIR.TXT || true)"
if grep -q 'require a destination directory' <<<"$output" \
    && [[ ! -e "$WORK/NOTDIR.TXT" ]]; then
    ok "multiple sources reject a filename destination"
else
    fail "multi-source filename rejection"
fi

output="$(run_expand BAD.TX_ BAD.OUT || true)"
if grep -q 'Invalid or truncated compressed file' <<<"$output" \
    && [[ ! -e "$WORK/BAD.OUT" ]]; then
    ok "invalid headers fail without leaving an output file"
else
    fail "invalid-header cleanup"
fi

output="$(run_expand SHORT.TX_ SHORT.OUT || true)"
if grep -q 'Invalid or truncated compressed file' <<<"$output" \
    && [[ ! -e "$WORK/SHORT.OUT" ]]; then
    ok "truncated streams remove their partial output"
else
    fail "truncated-stream cleanup"
fi

output="$(run_expand || true)"
if grep -q 'Invalid number of parameters' <<<"$output"; then
    ok "missing parameters return a clear error"
else
    fail "missing-parameter diagnostic"
fi

for tool in mcopy mmd nasm qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null || { echo "ERROR: missing $tool"; exit 1; }
done
QEMU_IMAGE="$WORK/EXPAND-QEMU.IMG"
QEMU_LOG="$WORK/EXPAND-QEMU.LOG"
QEXIT="$WORK/QEXIT.COM"
QEMU_RESULT="$WORK/QEMU-RESULT.TXT"
cp "$OUT/floppy.img" "$QEMU_IMAGE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
mcopy -o -i "$QEMU_IMAGE" "$QEXIT" ::QEXIT.COM
mcopy -o -i "$QEMU_IMAGE" "$WORK/ONE.TX_" ::ONE.TX_
mmd -i "$QEMU_IMAGE" ::OUTDIR
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'EXPAND ONE.TX_ OUTDIR\r\n'
    printf 'IF ERRORLEVEL 1 ECHO EXPAND_QEMU_ERROR\r\n'
    printf 'IF EXIST OUTDIR\\ONE.TXT ECHO EXPAND_QEMU_DONE\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$QEMU_IMAGE" - ::AUTOEXEC.BAT
timeout 15 qemu-system-i386 -display none -monitor none -machine pc -cpu 486 -m 4 \
    -drive if=floppy,index=0,format=raw,file="$QEMU_IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$QEMU_LOG" 2>&1 || true
mcopy -i "$QEMU_IMAGE" ::OUTDIR/ONE.TXT "$QEMU_RESULT" 2>/dev/null || true
if grep -q 'EXPAND_QEMU_DONE' "$QEMU_LOG" \
    && ! grep -q 'EXPAND_QEMU_ERROR' "$QEMU_LOG" \
    && cmp -s "$WORK/ONE.EXP" "$QEMU_RESULT"; then
    ok "real DOS recognizes a plain directory destination and expands byte-exactly"
else
    fail "real DOS directory-destination expansion"
fi

echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
