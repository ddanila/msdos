#!/bin/bash
# tests/test_wasm_boot.sh — Diagnostic: which WASM-built binary breaks boot?
#
# Strategy: Start from floppy.img (MASM baseline, known working).
# Swap one file at a time to WASM-built version and boot in headless QEMU.
# An AUTOEXEC.BAT redirects console to COM1 (AUX) and runs VER.
# A successful boot prints "MS-DOS Version" on serial.
#
# Tests:
#   A. floppy.img as-is (baseline)
#   B. floppy.img + WASM COMMAND.COM
#   C. floppy.img + WASM MSDOS.SYS
#   D. floppy.img + WASM MSDOS.SYS + WASM COMMAND.COM
#   E. floppy.img + WASM IO.SYS + WASM MSDOS.SYS + WASM COMMAND.COM (full WASM)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/MS-DOS/v4.0/src"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

WASM_IO="$SRC/BIOS/IO.SYS"
WASM_MSDOS="$SRC/DOS/MSDOS.SYS"
WASM_COMMAND="$SRC/CMD/COMMAND/COMMAND.COM"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

# Create a test image: start from floppy.img, optionally replace files,
# add AUTOEXEC.BAT with CTTY AUX + VER.
# Usage: make_test_img <output.img> [io|msdos|command ...]
make_test_img() {
    local out="$1"; shift
    local replacements=("$@")

    cp "$FLOPPY" "$out"

    # Optionally replace binaries
    for r in "${replacements[@]:-}"; do
        case "$r" in
            io)
                # Replace IO.SYS: must be first dir entry, contiguous at cluster 2.
                # Easier: rebuild whole image with WASM IO.SYS.
                # Instead, we note that mcopy -o replaces in-place only if same cluster
                # layout. Since IO.SYS is always first, we can delete and re-add,
                # but that changes dir order. Use python to patch raw bytes instead.
                python3 - "$out" "$WASM_IO" <<'PYEOF'
import sys, struct

img_path = sys.argv[1]
new_io_path = sys.argv[2]

data = bytearray(open(img_path, 'rb').read())
new_io = open(new_io_path, 'rb').read()
fat_start = 512
fat = data[fat_start:fat_start + 9*512]

def get_fat12(cluster):
    idx = cluster * 3 // 2
    if cluster % 2 == 0:
        return int.from_bytes(fat[idx:idx+2], 'little') & 0xFFF
    else:
        return (int.from_bytes(fat[idx:idx+2], 'little') >> 4) & 0xFFF

# IO.SYS is always at cluster 2 in our images
cluster = 2
buf = bytearray(new_io)
# Pad to full cluster multiple
while len(buf) % 512 != 0:
    buf += b'\x00'

offset_in_buf = 0
while cluster < 0xFF8 and offset_in_buf < len(buf):
    sector = (cluster - 2) + 33
    off = sector * 512
    data[off:off+512] = buf[offset_in_buf:offset_in_buf+512]
    offset_in_buf += 512
    cluster = get_fat12(cluster)

# Update directory entry size
dir_start = 19 * 512
# Entry 0 = IO.SYS
data[dir_start + 28:dir_start + 32] = struct.pack('<I', len(new_io))

open(img_path, 'wb').write(bytes(data))
print(f'  Patched IO.SYS: {len(new_io)} bytes')
PYEOF
                ;;
            msdos)
                # Replace MSDOS.SYS in-place (patch cluster chain data + dir size)
                python3 - "$out" "$WASM_MSDOS" <<'PYEOF'
import sys, struct

img_path = sys.argv[1]
new_file_path = sys.argv[2]

data = bytearray(open(img_path, 'rb').read())
new_file = open(new_file_path, 'rb').read()
fat_start = 512
fat = data[fat_start:fat_start + 9*512]

def get_fat12(cluster):
    idx = cluster * 3 // 2
    if cluster % 2 == 0:
        return int.from_bytes(fat[idx:idx+2], 'little') & 0xFFF
    else:
        return (int.from_bytes(fat[idx:idx+2], 'little') >> 4) & 0xFFF

# Find MSDOS.SYS dir entry (entry index 1)
dir_start = 19 * 512
entry = data[dir_start + 1*32 : dir_start + 1*32 + 32]
start_cluster = int.from_bytes(entry[26:28], 'little')
old_size = int.from_bytes(entry[28:32], 'little')

print(f'  MSDOS.SYS: cluster={start_cluster}, old_size={old_size}, new_size={len(new_file)}')

buf = bytearray(new_file)
while len(buf) % 512 != 0:
    buf += b'\x00'

cluster = start_cluster
offset_in_buf = 0
while cluster < 0xFF8 and offset_in_buf < len(buf):
    sector = (cluster - 2) + 33
    off = sector * 512
    data[off:off+512] = buf[offset_in_buf:offset_in_buf+512]
    offset_in_buf += 512
    cluster = get_fat12(cluster)

# Update dir entry size
data[dir_start + 1*32 + 28 : dir_start + 1*32 + 32] = struct.pack('<I', len(new_file))

open(img_path, 'wb').write(bytes(data))
print(f'  Patched MSDOS.SYS OK')
PYEOF
                ;;
            command)
                # Replace COMMAND.COM (entry index 2)
                python3 - "$out" "$WASM_COMMAND" <<'PYEOF'
import sys, struct

img_path = sys.argv[1]
new_file_path = sys.argv[2]

data = bytearray(open(img_path, 'rb').read())
new_file = open(new_file_path, 'rb').read()
fat_start = 512
fat = data[fat_start:fat_start + 9*512]

def get_fat12(cluster):
    idx = cluster * 3 // 2
    if cluster % 2 == 0:
        return int.from_bytes(fat[idx:idx+2], 'little') & 0xFFF
    else:
        return (int.from_bytes(fat[idx:idx+2], 'little') >> 4) & 0xFFF

# Find COMMAND.COM dir entry (entry index 2)
dir_start = 19 * 512
entry = data[dir_start + 2*32 : dir_start + 2*32 + 32]
start_cluster = int.from_bytes(entry[26:28], 'little')
old_size = int.from_bytes(entry[28:32], 'little')

print(f'  COMMAND.COM: cluster={start_cluster}, old_size={old_size}, new_size={len(new_file)}')

buf = bytearray(new_file)
while len(buf) % 512 != 0:
    buf += b'\x00'

cluster = start_cluster
offset_in_buf = 0
while cluster < 0xFF8 and offset_in_buf < len(buf):
    sector = (cluster - 2) + 33
    off = sector * 512
    data[off:off+512] = buf[offset_in_buf:offset_in_buf+512]
    offset_in_buf += 512
    cluster = get_fat12(cluster)

# Update dir entry size
data[dir_start + 2*32 + 28 : dir_start + 2*32 + 32] = struct.pack('<I', len(new_file))

open(img_path, 'wb').write(bytes(data))
print(f'  Patched COMMAND.COM OK')
PYEOF
                ;;
        esac
    done

    # Add AUTOEXEC.BAT: redirect console to COM1, print DOS version
    printf 'CTTY AUX\r\nVER\r\n' | mcopy -i "$out" - ::AUTOEXEC.BAT
}

# Boot image headlessly, capture serial output, check for "MS-DOS"
boot_test() {
    local label="$1"
    local img="$2"
    local log="${img%.img}.log"

    echo ""
    echo "=== $label ==="
    timeout 12 qemu-system-i386 \
        -fda "$img" -boot a -m 4 \
        -display none \
        -serial stdio \
        2>/dev/null > "$log" || true

    if grep -qi "MS-DOS" "$log" 2>/dev/null; then
        ok "$label — boots to DOS prompt"
    else
        fail "$label — no DOS prompt"
        echo "    serial output: $(head -3 "$log" 2>/dev/null | tr '\r\n' ' ')"
    fi
}

echo "Building test images..."

# A: baseline (MASM floppy + AUTOEXEC.BAT only)
echo "A: baseline (all MASM)"
make_test_img "$OUT/wasm-test-A.img"
boot_test "A: baseline MASM" "$OUT/wasm-test-A.img"

# B: WASM COMMAND.COM only
echo "B: WASM COMMAND.COM"
make_test_img "$OUT/wasm-test-B.img" command
boot_test "B: WASM COMMAND.COM" "$OUT/wasm-test-B.img"

# C: WASM MSDOS.SYS only
echo "C: WASM MSDOS.SYS"
make_test_img "$OUT/wasm-test-C.img" msdos
boot_test "C: WASM MSDOS.SYS" "$OUT/wasm-test-C.img"

# D: WASM MSDOS.SYS + COMMAND.COM
echo "D: WASM MSDOS.SYS + COMMAND.COM"
make_test_img "$OUT/wasm-test-D.img" msdos command
boot_test "D: WASM MSDOS.SYS + COMMAND.COM" "$OUT/wasm-test-D.img"

# E: All WASM (IO.SYS + MSDOS.SYS + COMMAND.COM)
echo "E: All WASM"
make_test_img "$OUT/wasm-test-E.img" io msdos command
boot_test "E: All WASM" "$OUT/wasm-test-E.img"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
