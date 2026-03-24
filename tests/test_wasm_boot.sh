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
                # Replace IO.SYS (dir entry 0, starts at cluster 2)
                # Uses same FAT chain extension logic as MSDOS.SYS/COMMAND.COM
                python3 - "$out" "$WASM_IO" 0 "IO.SYS" <<'PYEOF'
import sys, struct
img_path, new_file_path = sys.argv[1], sys.argv[2]
dir_idx, label = int(sys.argv[3]), sys.argv[4]
data = bytearray(open(img_path, 'rb').read())
new_file = open(new_file_path, 'rb').read()
FAT1 = 512; FAT2 = 512 + 9*512; FAT_SZ = 9*512
fat = bytearray(data[FAT1:FAT1+FAT_SZ])

def get_fat12(c):
    i = c*3//2
    return (int.from_bytes(fat[i:i+2],'little') & 0xFFF) if c%2==0 else (int.from_bytes(fat[i:i+2],'little')>>4) & 0xFFF

def set_fat12(c, val):
    i = c*3//2
    old = int.from_bytes(fat[i:i+2],'little')
    if c%2==0:
        new = (old & 0xF000) | (val & 0xFFF)
    else:
        new = (old & 0x000F) | ((val & 0xFFF) << 4)
    fat[i:i+2] = new.to_bytes(2,'little')

dir_start = 19*512
entry = data[dir_start+dir_idx*32:dir_start+dir_idx*32+32]
start_cluster = int.from_bytes(entry[26:28],'little')
old_size = int.from_bytes(entry[28:32],'little')

buf = bytearray(new_file)
while len(buf) % 512: buf += b'\x00'
sectors_needed = len(buf) // 512

# Collect existing chain
chain = []
c = start_cluster
while c >= 2 and c < 0xFF8:
    chain.append(c)
    c = get_fat12(c)

# Extend chain if needed
while len(chain) < sectors_needed:
    for fc in range(2, (len(data)//512 - 33) + 2):
        if get_fat12(fc) == 0:
            set_fat12(chain[-1], fc)
            set_fat12(fc, 0xFFF)
            chain.append(fc)
            break
    else:
        print(f'  ERROR: disk full', file=sys.stderr); sys.exit(1)

# Shrink chain if new file is smaller
for i in range(sectors_needed, len(chain)):
    set_fat12(chain[i], 0)
if sectors_needed > 0 and sectors_needed < len(chain):
    set_fat12(chain[sectors_needed-1], 0xFFF)
chain = chain[:sectors_needed]

# Write data
for i, cl in enumerate(chain):
    off = (cl - 2 + 33) * 512
    data[off:off+512] = buf[i*512:(i+1)*512]

# Write both FATs + dir size
data[FAT1:FAT1+FAT_SZ] = fat
data[FAT2:FAT2+FAT_SZ] = fat
data[dir_start+dir_idx*32+28:dir_start+dir_idx*32+32] = struct.pack('<I', len(new_file))
open(img_path, 'wb').write(bytes(data))
print(f'  Patched {label}: {len(new_file)} bytes')
PYEOF
                ;;
            msdos)
                # Replace MSDOS.SYS — extends FAT chain if new file is larger
                python3 - "$out" "$WASM_MSDOS" 1 "MSDOS.SYS" <<'PYEOF'
import sys, struct
img_path, new_file_path = sys.argv[1], sys.argv[2]
dir_idx, label = int(sys.argv[3]), sys.argv[4]
data = bytearray(open(img_path, 'rb').read())
new_file = open(new_file_path, 'rb').read()
FAT1 = 512; FAT2 = 512 + 9*512; FAT_SZ = 9*512
fat = bytearray(data[FAT1:FAT1+FAT_SZ])

def get_fat12(c):
    i = c*3//2
    return (int.from_bytes(fat[i:i+2],'little') & 0xFFF) if c%2==0 else (int.from_bytes(fat[i:i+2],'little')>>4) & 0xFFF

def set_fat12(c, val):
    i = c*3//2
    old = int.from_bytes(fat[i:i+2],'little')
    if c%2==0:
        new = (old & 0xF000) | (val & 0xFFF)
    else:
        new = (old & 0x000F) | ((val & 0xFFF) << 4)
    fat[i:i+2] = new.to_bytes(2,'little')

dir_start = 19*512
entry = data[dir_start+dir_idx*32:dir_start+dir_idx*32+32]
start_cluster = int.from_bytes(entry[26:28],'little')
old_size = int.from_bytes(entry[28:32],'little')
print(f'  {label}: cluster={start_cluster}, old_size={old_size}, new_size={len(new_file)}')

buf = bytearray(new_file)
while len(buf) % 512: buf += b'\x00'
sectors_needed = len(buf) // 512

# Collect existing chain
chain = []
c = start_cluster
while c >= 2 and c < 0xFF8:
    chain.append(c)
    c = get_fat12(c)

# Extend chain if needed
while len(chain) < sectors_needed:
    for fc in range(2, (len(data)//512 - 33) + 2):
        if get_fat12(fc) == 0:
            set_fat12(chain[-1], fc)
            set_fat12(fc, 0xFFF)
            chain.append(fc)
            break
    else:
        print(f'  ERROR: disk full, need {sectors_needed} clusters, have {len(chain)}', file=sys.stderr)
        sys.exit(1)

# Shrink chain if new file is smaller
for i in range(sectors_needed, len(chain)):
    set_fat12(chain[i], 0)
if sectors_needed > 0 and sectors_needed < len(chain):
    set_fat12(chain[sectors_needed-1], 0xFFF)
chain = chain[:sectors_needed]

# Write data
for i, cl in enumerate(chain):
    off = (cl - 2 + 33) * 512
    data[off:off+512] = buf[i*512:(i+1)*512]

# Write both FATs + dir size
data[FAT1:FAT1+FAT_SZ] = fat
data[FAT2:FAT2+FAT_SZ] = fat
data[dir_start+dir_idx*32+28:dir_start+dir_idx*32+32] = struct.pack('<I', len(new_file))
open(img_path, 'wb').write(bytes(data))
print(f'  Patched {label} OK')
PYEOF
                ;;
            command)
                # Replace COMMAND.COM — extends FAT chain if new file is larger
                python3 - "$out" "$WASM_COMMAND" 2 "COMMAND.COM" <<'PYEOF'
import sys, struct
img_path, new_file_path = sys.argv[1], sys.argv[2]
dir_idx, label = int(sys.argv[3]), sys.argv[4]
data = bytearray(open(img_path, 'rb').read())
new_file = open(new_file_path, 'rb').read()
FAT1 = 512; FAT2 = 512 + 9*512; FAT_SZ = 9*512
fat = bytearray(data[FAT1:FAT1+FAT_SZ])

def get_fat12(c):
    i = c*3//2
    return (int.from_bytes(fat[i:i+2],'little') & 0xFFF) if c%2==0 else (int.from_bytes(fat[i:i+2],'little')>>4) & 0xFFF

def set_fat12(c, val):
    i = c*3//2
    old = int.from_bytes(fat[i:i+2],'little')
    if c%2==0:
        new = (old & 0xF000) | (val & 0xFFF)
    else:
        new = (old & 0x000F) | ((val & 0xFFF) << 4)
    fat[i:i+2] = new.to_bytes(2,'little')

dir_start = 19*512
entry = data[dir_start+dir_idx*32:dir_start+dir_idx*32+32]
start_cluster = int.from_bytes(entry[26:28],'little')
old_size = int.from_bytes(entry[28:32],'little')
print(f'  {label}: cluster={start_cluster}, old_size={old_size}, new_size={len(new_file)}')

buf = bytearray(new_file)
while len(buf) % 512: buf += b'\x00'
sectors_needed = len(buf) // 512

# Collect existing chain
chain = []
c = start_cluster
while c >= 2 and c < 0xFF8:
    chain.append(c)
    c = get_fat12(c)

# Extend chain if needed
while len(chain) < sectors_needed:
    for fc in range(2, (len(data)//512 - 33) + 2):
        if get_fat12(fc) == 0:
            set_fat12(chain[-1], fc)
            set_fat12(fc, 0xFFF)
            chain.append(fc)
            break
    else:
        print(f'  ERROR: disk full, need {sectors_needed} clusters, have {len(chain)}', file=sys.stderr)
        sys.exit(1)

# Shrink chain if new file is smaller
for i in range(sectors_needed, len(chain)):
    set_fat12(chain[i], 0)
if sectors_needed > 0 and sectors_needed < len(chain):
    set_fat12(chain[sectors_needed-1], 0xFFF)
chain = chain[:sectors_needed]

# Write data
for i, cl in enumerate(chain):
    off = (cl - 2 + 33) * 512
    data[off:off+512] = buf[i*512:(i+1)*512]

# Write both FATs + dir size
data[FAT1:FAT1+FAT_SZ] = fat
data[FAT2:FAT2+FAT_SZ] = fat
data[dir_start+dir_idx*32+28:dir_start+dir_idx*32+32] = struct.pack('<I', len(new_file))
open(img_path, 'wb').write(bytes(data))
print(f'  Patched {label} OK')
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
