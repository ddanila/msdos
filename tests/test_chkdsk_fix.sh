#!/bin/bash
# tests/test_chkdsk_fix.sh — E2E test for CHKDSK /F (fix errors) via QEMU.
#
# Tests CHKDSK's ability to detect and fix FAT12 filesystem errors:
#   1. Lost clusters (orphans): FAT entries allocated but not referenced by any file
#   2. CHKDSK /F: prompts "Convert lost chains to files (Y/N)?", fixes on Y
#   3. Post-fix: CHKDSK B: verifies disk is clean after repair
#
# Test setup:
#   - Boot floppy A: carries CHKDSK.COM and the batch script
#   - Target floppy B: fresh blank floppy, then FAT is corrupted with Python
#     to create orphan clusters (allocated in FAT but no directory entry)
#   - AUTOEXEC.BAT runs CHKDSK B: /F (fix), DIR (verify), CHKDSK B: (clean)
#
# Interactive prompt handling:
#   CHKDSK /F prompts "Convert lost chains to files (Y/N)?" via SYSDISPMSG
#   (INT 21h function 8, reads from handle 0 = COM1 with CTTY AUX).
#   serial_expect.py detects the prompt and sends "Y\r" to convert orphans
#   to FILE0000.CHK, FILE0001.CHK, etc.
#
#   IMPORTANT: SYSDISPMSG requires CR (0x0D) after the Y/N character.
#   Sending just "Y" without \r causes CHKDSK to hang waiting for Enter.
#
# FAT12 floppy layout (1.44 MB):
#   Sector 0:     boot sector (BPB)
#   Sectors 1-9:  FAT1 (9 sectors, 12-bit entries, clusters 0-2879)
#   Sectors 10-18: FAT2 (backup)
#   Sectors 19-32: root directory (224 entries × 32 bytes)
#   Sectors 33+:  data area (cluster 2 = sector 33)
#
# Run via: make test-chkdsk-fix  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

BOOT_IMG="$OUT/chkdsk-boot.img"
TARGET_IMG="$OUT/chkdsk-target.img"
SERIAL_LOG="$OUT/chkdsk-fix-serial.log"
SERIAL_IN="$OUT/chkdsk-fix-serial.in"
SERIAL_OUT="$OUT/chkdsk-fix-serial.out"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'rm -f "$SERIAL_IN" "$SERIAL_OUT" 2>/dev/null; true' EXIT

echo "=== CHKDSK /F E2E tests (QEMU, interactive serial expect) ==="

export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

# ── Step 1: build images ────────────────────────────────────────────────────
echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"

# Create a fresh blank FAT12 floppy for the target (not a copy of the boot floppy,
# which has ~48 files occupying many clusters). We need free clusters 100-102.
dd if=/dev/zero of="$TARGET_IMG" bs=512 count=2880 status=none
mformat -i "$TARGET_IMG" ::

# Create a test file on the target floppy so it has some content
printf 'Hello from CHKDSK test\r\n' | mcopy -o -i "$TARGET_IMG" - ::CHKTEST.TXT

# ── Step 2: corrupt FAT to create orphan clusters ───────────────────────────
# Mark clusters 100-102 as an allocated chain in FAT1 and FAT2, but no
# directory entry references them. CHKDSK will detect these as lost clusters.
#
# FAT12 encoding: each entry is 12 bits (1.5 bytes).
#   Cluster N at byte offset (N * 3 / 2) within the FAT.
#   If N is even: low 12 bits of the 16-bit word at that offset.
#   If N is odd:  high 12 bits of the 16-bit word at that offset.
#
# Chain: cluster 100 → 101 → 102 → EOF (0xFFF)
# FAT1 starts at byte offset 512 (sector 1), FAT2 at byte offset 512*10=5120.
echo "Corrupting FAT to create orphan clusters..."
python3 -c "
import struct

with open('$TARGET_IMG', 'r+b') as f:
    def read_fat12(fat_off, cluster):
        byte_off = fat_off + (cluster * 3) // 2
        f.seek(byte_off)
        word = struct.unpack('<H', f.read(2))[0]
        if cluster % 2 == 0:
            return word & 0xFFF
        else:
            return (word >> 4) & 0xFFF

    def write_fat12(fat_off, cluster, value):
        byte_off = fat_off + (cluster * 3) // 2
        f.seek(byte_off)
        word = struct.unpack('<H', f.read(2))[0]
        if cluster % 2 == 0:
            word = (word & 0xF000) | (value & 0xFFF)
        else:
            word = (word & 0x000F) | ((value & 0xFFF) << 4)
        f.seek(byte_off)
        f.write(struct.pack('<H', word))

    FAT1_OFF = 512       # sector 1
    FAT2_OFF = 512 * 10  # sector 10

    # Verify clusters 100-102 are free (should be 0x000)
    for c in [100, 101, 102]:
        v = read_fat12(FAT1_OFF, c)
        assert v == 0, f'Cluster {c} already in use: 0x{v:03X}'

    # Create orphan chain: 100 → 101 → 102 → EOF
    for fat_off in [FAT1_OFF, FAT2_OFF]:
        write_fat12(fat_off, 100, 101)   # 100 → 101
        write_fat12(fat_off, 101, 102)   # 101 → 102
        write_fat12(fat_off, 102, 0xFFF) # 102 → EOF

    # Verify the chain
    for fat_off in [FAT1_OFF, FAT2_OFF]:
        assert read_fat12(fat_off, 100) == 101
        assert read_fat12(fat_off, 101) == 102
        assert read_fat12(fat_off, 102) == 0xFFF

    print('FAT corrupted: orphan chain 100 -> 101 -> 102 -> EOF in FAT1+FAT2')
" || { echo "ERROR: FAT corruption script failed"; exit 1; }

# ── Step 3: write AUTOEXEC.BAT ──────────────────────────────────────────────
{
    printf 'CTTY AUX\r\n'

    # First: CHKDSK B: /F — fix errors (will prompt Y/N for orphan recovery)
    printf 'ECHO ---CHKDSK-FIX---\r\n'
    printf 'CHKDSK B: /F\r\n'
    printf 'ECHO CHKDSK_FIX_DONE\r\n'

    # Second: verify FILE0000.CHK was created on B:
    printf 'ECHO ---CHKDSK-VERIFY---\r\n'
    printf 'DIR B:\\FILE0000.CHK\r\n'
    printf 'ECHO CHKDSK_VERIFY_DONE\r\n'

    # Third: CHKDSK B: — verify disk is now clean (no errors after fix)
    printf 'ECHO ---CHKDSK-CLEAN---\r\n'
    printf 'CHKDSK B:\r\n'
    printf 'ECHO CHKDSK_CLEAN_DONE\r\n'

    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# ── Step 4: set up serial FIFOs ─────────────────────────────────────────────
rm -f "$SERIAL_IN" "$SERIAL_OUT"
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"    # O_RDWR: keeps read-end alive so QEMU/Python O_WRONLY won't block

# ── Step 5: boot QEMU ───────────────────────────────────────────────────────
echo "Booting QEMU with CHKDSK /F test..."
rm -f "$SERIAL_LOG"
timeout 120 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="$TARGET_IMG",cache=writethrough \
    -boot a -m 4 \
    -serial pipe:"$OUT/chkdsk-fix-serial" \
    2>/dev/null &
QEMU_PID=$!

# ── Step 6: run serial expect coordinator ────────────────────────────────────
# Interaction: "Convert lost chains to files (Y/N)?" — from CHKDSK /F, respond Y
python3 "$REPO_ROOT/tests/serial_expect.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$SERIAL_LOG" \
    "Convert lost chains to files" 'Y\r'

wait $QEMU_PID || true
exec 3>&-    # close our O_RDWR fd on SERIAL_IN

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

# ── Step 7: checks ──────────────────────────────────────────────────────────
echo ""
echo "--- CHKDSK /F (fix) ---"

if grep -q "CHKDSK_FIX_DONE" "$SERIAL_LOG"; then
    ok "CHKDSK B: /F completed (fix mode)"
else
    fail "CHKDSK B: /F (batch hung or crashed — prompt not answered?)"
fi

# Should have prompted for conversion
if grep -qi "Convert lost chains" "$SERIAL_LOG"; then
    ok "CHKDSK /F prompted 'Convert lost chains to files'"
else
    fail "CHKDSK /F (expected 'Convert lost chains' prompt)"
fi

# Should report lost clusters
if grep -qi "lost.*allocation unit\|lost cluster" "$SERIAL_LOG"; then
    ok "CHKDSK /F detected lost allocation units"
else
    fail "CHKDSK /F (expected 'lost allocation units' in output)"
fi

# Should report recovered files
if grep -qi "recovered file" "$SERIAL_LOG"; then
    ok "CHKDSK /F reported recovered files"
else
    fail "CHKDSK /F (expected 'recovered file' in output)"
fi

echo ""
echo "--- Verification ---"

if grep -q "CHKDSK_VERIFY_DONE" "$SERIAL_LOG"; then
    ok "DIR B:\\FILE0000.CHK completed"
else
    fail "DIR B:\\FILE0000.CHK (batch hung or crashed)"
fi

# FILE0000.CHK should appear in the DIR listing
if grep -qi "FILE0000.*CHK" "$SERIAL_LOG"; then
    ok "FILE0000.CHK exists on B: (orphan chain recovered to file)"
else
    fail "FILE0000.CHK not found on B: (recovery may have failed)"
fi

echo ""
echo "--- Post-fix verification (CHKDSK B: without /F) ---"

if grep -q "CHKDSK_CLEAN_DONE" "$SERIAL_LOG"; then
    ok "CHKDSK B: (post-fix) completed"
else
    fail "CHKDSK B: (post-fix batch hung or crashed)"
fi

# After fix, CHKDSK should NOT report errors (no "Errors found" or lost clusters)
if grep -q "CHKDSK_CLEAN_DONE" "$SERIAL_LOG" && \
   ! sed -n '/---CHKDSK-CLEAN---/,/CHKDSK_CLEAN_DONE/p' "$SERIAL_LOG" | grep -qi "lost.*allocation unit\|Errors found"; then
    ok "CHKDSK B: (post-fix) reports clean disk — no errors"
else
    fail "CHKDSK B: (post-fix) still reports errors after fix"
fi

echo ""
if grep -q "===DONE===" "$SERIAL_LOG"; then
    ok "Batch reached ===DONE==="
else
    fail "Batch did NOT reach ===DONE=== (hung or crashed early)"
    echo "--- last 30 lines of serial log ---"
    tail -30 "$SERIAL_LOG"
    echo "---"
fi

# Dump serial log on any failure
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "--- full serial log (for debugging) ---"
    cat "$SERIAL_LOG" 2>/dev/null || echo "(empty)"
    echo "--- end serial log ---"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
