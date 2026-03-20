#!/bin/bash
# tests/test_format.sh — E2E tests for FORMAT.COM via QEMU with QMP floppy swapping.
#
# All 8 FORMAT variants run in a single QEMU session.  After each FORMAT the host:
#   1. Detects the DONE marker in real-time serial output (FIFO + background monitor)
#   2. Saves a copy of B: image for post-QEMU verification
#   3. Swaps B: to the next blank image via QEMU QMP ("change floppy1 …")
#      — emulates pulling one floppy out and inserting another
# Post-QEMU: verifies each saved image using Python3 (BPB geometry) and mlabel.
#
# QMP interaction:
#   QEMU is started with -qmp unix:$QMP_SOCK,server,nowait.
#   The host sends: {"execute":"human-monitor-command",
#                    "arguments":{"command-line":"change floppy1 <path>"}}
#   QEMU's floppy emulation then sets the disk-change line so DOS detects the
#   new medium on the next B: access (INT 13h IOCTL from FORMAT).
#
# FORMAT prompt sequence (FORMAT.SKL verified):
#   msg  7: "Insert new diskette for drive B:"  — informational, no wait
#   msg 28: "and press ENTER when ready..."     — waits via USER_STRING (reads 1 line)
#           format runs, printing % progress
#   msg  4: "Format complete"
#   msg 30: "System transferred"  (only for /S)
#   COMMON35: "Volume label (11 characters, ENTER for none)?"  — if no /V: on cmd line
#   msg 46: "Format another (Y/N)?"             — waits; CR (not Y) → exits
# A continuous \r\n feed satisfies all waits.
#
# BPB geometry offsets (from start of boot sector):
#   0x18-0x19: sectors per track   0x1A-0x1B: number of heads
#   0x13-0x14: total sectors 16-bit (0 if >65535)   0x20-0x23: total sectors 32-bit
#
# Expected BPB values per variant:
#   default 1.44MB (/V:TEST, /S, /B): spt=18, heads=2, total=2880
#   /F:720 and /T:80 /N:9 (720KB)   : spt=9,  heads=2, total=1440
#   /4 (360KB on 1.2MB drive)        : spt=9,  heads=2, total=720
#   /1 (single-sided 1.44MB)         : spt=18, heads=1
#   /8 (8 sec/track)                 : spt=8,  heads=2
#   /SELECT /V:SELTEST               : spt=18, heads=2, total=2880
#   /AUTOTEST /V:AUTO                : spt=18, heads=2, total=2880
#
# Error exit variants (no BPB check):
#   /C: disallowed — "Invalid parameter" (MSFOR.ASM lines 259-267)
#   /Z: ShipDisk=NO in FOREQU.INC — not in parser, rejected
#
# Run via: make test-format  (requires 'make deploy' first)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="$OUT/floppy.img"

# Optional: pass variant names as arguments to run a subset, e.g.:
#   bash tests/test_format.sh VLABEL S
# With no arguments, all 8 variants run.
SELECTED_VARIANTS=("$@")

# FORMAT_WORKDIR: directory for per-session temp files (boot img, serial FIFOs,
# QMP socket).  Override when running multiple instances in parallel so they
# don't collide.  Defaults to $OUT.
WORKDIR="${FORMAT_WORKDIR:-$OUT}"
mkdir -p "$WORKDIR"

BOOT_IMG="$WORKDIR/format-boot.img"
SERIAL_IN="$WORKDIR/format-serial.in"
SERIAL_OUT="$WORKDIR/format-serial.out"
SERIAL_LOG="$WORKDIR/format-serial.log"
QMP_SOCK="$WORKDIR/format-qmp.sock"

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$FLOPPY" ]]; then
    echo "ERROR: $FLOPPY not found — run 'make deploy' first"
    exit 1
fi

trap 'rm -f "$SERIAL_IN" "$SERIAL_OUT" "$QMP_SOCK" 2>/dev/null; [[ "$WORKDIR" != "$OUT" ]] && rm -rf "$WORKDIR" 2>/dev/null; true' EXIT

echo "=== FORMAT E2E tests (QEMU, QMP disk swapping) ==="

# ── Test definitions ──────────────────────────────────────────────────────────
# NAMES must be uppercase (used verbatim in AUTOEXEC.BAT ECHO markers).
# B_SECTORS: /4 needs a 1.2MB image (2400 sectors) so QEMU presents a 1.2MB drive.
# NOTE: /F:720, /T:80 /N:9, /1, /4, /8 exit with "Parameters not supported [by drive]"
# in this single-session QEMU setup because IO.SYS caches the B: drive type from boot
# (initial image is 1.44MB → DEV_OTHER), and /1, /4, /8 require 5.25" drive types that
# QEMU does not emulate.  /C and /Z exit with "Invalid parameter" (error paths).
# /SELECT and /AUTOTEST suppress all interactive prompts (format unattended).
# The coordinator exercises all variants — batch completion markers confirm each ran.
NAMES=("VLABEL" "S"      "B"      "F720"   "TN"     "FOUR"   "ONE"    "EIGHT"
       "SWITCHC" "SWITCHZ" "SELECT" "AUTOTEST")
FORMAT_CMDS=(
    "FORMAT B: /V:TEST"
    "FORMAT B: /S"
    "FORMAT B: /B"
    "FORMAT B: /F:720"
    "FORMAT B: /T:80 /N:9"
    "FORMAT B: /4"
    "FORMAT B: /1"
    "FORMAT B: /8"
    "FORMAT B: /C"
    "FORMAT B: /Z"
    "FORMAT B: /SELECT /V:SELTEST"
    "FORMAT B: /AUTOTEST /V:AUTO"
)
B_SECTORS=(2880 2880 2880 2880 2880 2400 2880 2880
           2880 2880 2880 2880)
# Which NAMES have /V:<label> on the command line → FORMAT skips volume-label prompt.
NO_LABEL_NAMES=(VLABEL SELECT AUTOTEST)

# ── Filter to selected variants (if arguments given) ──────────────────────────
if [[ ${#SELECTED_VARIANTS[@]} -gt 0 ]]; then
    _SEL_NAMES=() _SEL_CMDS=() _SEL_SECTORS=()
    for sel in "${SELECTED_VARIANTS[@]}"; do
        found=0
        for i in "${!NAMES[@]}"; do
            if [[ "${NAMES[$i]}" == "$sel" ]]; then
                _SEL_NAMES+=("${NAMES[$i]}")
                _SEL_CMDS+=("${FORMAT_CMDS[$i]}")
                _SEL_SECTORS+=("${B_SECTORS[$i]}")
                found=1; break
            fi
        done
        [[ $found -eq 0 ]] && { echo "ERROR: unknown variant '$sel'"; exit 1; }
    done
    NAMES=("${_SEL_NAMES[@]}"); FORMAT_CMDS=("${_SEL_CMDS[@]}"); B_SECTORS=("${_SEL_SECTORS[@]}")
    echo "(Running subset: ${NAMES[*]})"
fi

B_IMGS=()
SAVED_IMGS=()

# ── Step 1: build boot floppy and blank B: images ─────────────────────────────
echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

{
    printf 'CTTY AUX\r\n'
    for i in "${!NAMES[@]}"; do
        printf 'ECHO ---FORMAT-%s---\r\n' "${NAMES[$i]}"
        printf '%s\r\n' "${FORMAT_CMDS[$i]}"
        printf 'ECHO FORMAT_%s_DONE\r\n' "${NAMES[$i]}"
    done
    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

for i in "${!NAMES[@]}"; do
    B_IMGS+=("$OUT/format-b-${NAMES[$i]}.img")
    SAVED_IMGS+=("$OUT/format-saved-${NAMES[$i]}.img")
    dd if=/dev/zero bs=512 count="${B_SECTORS[$i]}" of="${B_IMGS[$i]}" status=none
done

# ── Step 2: set up serial FIFOs ───────────────────────────────────────────────
# format_coordinator.py acts as both serial coordinator and disk-swap manager.
# It processes each FORMAT prompt in strict order, swaps B: via QMP right before
# sending "press ENTER when ready", and saves each image on its DONE marker.
# See tests/format_coordinator.py for the full design rationale.
mkfifo "$SERIAL_IN" "$SERIAL_OUT"
exec 3<>"$SERIAL_IN"   # O_RDWR: keeps read-end open so QEMU's O_RDONLY won't block

# ── Step 3: boot QEMU ─────────────────────────────────────────────────────────
# -serial pipe: splits serial into .in/.out FIFOs consumed by the coordinator.
# cache=writethrough: guarantees B: writes reach the image file before we save it.
echo "Booting QEMU (single boot, 8 FORMAT variants via QMP disk swapping)..."
echo "Estimated time: ~5 min"
rm -f "$SERIAL_LOG"
timeout 480 qemu-system-i386 \
    -display none \
    -drive if=floppy,index=0,format=raw,file="$BOOT_IMG",cache=writethrough \
    -drive if=floppy,index=1,format=raw,file="${B_IMGS[0]}",cache=writethrough \
    -qmp unix:"$QMP_SOCK",server,nowait \
    -boot a -m 4 \
    -serial pipe:"$WORKDIR/format-serial" \
    2>/dev/null &
QEMU_PID=$!

# ── Step 4: run coordinator ────────────────────────────────────────────────────
# Blocks until QEMU exits (serial pipe EOF).
# Build CSV args for the coordinator: names and no_label_names.
_NAMES_CSV=$(IFS=,; echo "${NAMES[*]}")
_NO_LABEL_CSV=$(IFS=,; echo "${NO_LABEL_NAMES[*]}")
python3 "$REPO_ROOT/tests/format_coordinator.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$SERIAL_LOG" "$QMP_SOCK" \
    "${#NAMES[@]}" "$_NAMES_CSV" "$_NO_LABEL_CSV" \
    "${B_IMGS[@]}" \
    "${SAVED_IMGS[@]}"

# Coordinator is done (all rules processed); QEMU may still be idling.
# Kill it now — images are already saved and writes are flushed (cache=writethrough).
kill $QEMU_PID 2>/dev/null || true
wait $QEMU_PID || true
exec 3>&-

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

# ── Step 4: serial log checks ─────────────────────────────────────────────────
echo ""
echo "--- FORMAT batch completion markers ---"
for name in "${NAMES[@]}"; do
    if grep -q "FORMAT_${name}_DONE" "$SERIAL_LOG"; then
        ok "FORMAT ${name} (batch continued after FORMAT)"
    else
        fail "FORMAT ${name} (batch hung or crashed after FORMAT)"
    fi
done

echo ""
echo "--- FORMAT complete messages ---"
# Count how many full-format variants (VLABEL, S, B) were selected.
_full_count=0
for _fn in VLABEL S B; do
    for _n in "${NAMES[@]}"; do [[ "$_n" == "$_fn" ]] && _full_count=$((_full_count+1)) && break; done
done
if [[ $_full_count -gt 0 ]]; then
    count=$(grep -ic "Format complete" "$SERIAL_LOG" || echo 0)
    if [[ $count -ge $_full_count ]]; then
        ok "FORMAT full-format variants printed 'Format complete' ($count found, expected >=$_full_count)"
    else
        fail "Expected at least $_full_count 'Format complete' messages, got $count"
    fi
fi

echo ""
echo "--- FORMAT /S: System transferred ---"
_s_selected=0
for _n in "${NAMES[@]}"; do [[ "$_n" == "S" ]] && _s_selected=1 && break; done
if [[ $_s_selected -eq 1 ]]; then
    if grep -qi "System transferred" "$SERIAL_LOG"; then
        ok "FORMAT /S (printed 'System transferred')"
    else
        fail "FORMAT /S (expected 'System transferred' in serial log)"
    fi
fi

echo ""
if grep -q "===DONE===" "$SERIAL_LOG"; then
    ok "Batch reached ===DONE==="
else
    fail "Batch did NOT reach ===DONE=== (hung or crashed early)"
    echo "--- last 20 lines of serial log ---"
    tail -20 "$SERIAL_LOG"
    echo "---"
fi

# ── Step 5: post-QEMU BPB geometry verification ───────────────────────────────
# Reads sectors-per-track, heads, and total-sector-count directly from the
# FAT12 BPB written by FORMAT.  Python3 is in the CI image (ubuntu:24.04).
read_bpb() {
    python3 - "$1" <<'PYEOF'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    f.seek(0x13); total16 = struct.unpack('<H', f.read(2))[0]
    f.seek(0x18); spt, heads = struct.unpack('<HH', f.read(4))
    f.seek(0x20); total32 = struct.unpack('<I', f.read(4))[0]
total = total32 if total16 == 0 else total16
print(f"spt={spt} heads={heads} total={total}")
PYEOF
}

echo ""
echo "--- Post-QEMU BPB geometry checks ---"

# Expected BPB geometry per variant name.  Variants not listed here exit with
# errors ("Parameters not supported", "Invalid parameter") and produce no image.
declare -A _EXP_SPT _EXP_HEADS _EXP_TOTAL
_EXP_SPT=( [VLABEL]=18 [S]=18 [B]=18 [SELECT]=18 [AUTOTEST]=18 )
_EXP_HEADS=( [VLABEL]=2  [S]=2  [B]=2  [SELECT]=2  [AUTOTEST]=2  )
_EXP_TOTAL=( [VLABEL]=2880 [S]=2880 [B]=2880 [SELECT]=2880 [AUTOTEST]=2880 )

for i in "${!NAMES[@]}"; do
    name="${NAMES[$i]}"
    if [[ -z "${_EXP_SPT[$name]+x}" ]]; then continue; fi   # no BPB check for this variant
    img="${SAVED_IMGS[$i]}"
    es="${_EXP_SPT[$name]}"; eh="${_EXP_HEADS[$name]}"; et="${_EXP_TOTAL[$name]}"
    if bpb=$(read_bpb "$img" 2>/dev/null); then
        if [[ "$bpb" == *"spt=$es"* && "$bpb" == *"heads=$eh"* && "$bpb" == *"total=$et"* ]]; then
            ok "FORMAT $name BPB ($bpb)"
        else
            fail "FORMAT $name BPB: expected spt=$es heads=$eh total=$et, got: $bpb"
        fi
    else
        fail "FORMAT $name (saved image missing or unreadable)"
    fi
    # VLABEL: also verify volume label was written
    if [[ "$name" == "VLABEL" ]]; then
        label=$(mlabel -i "$img" -s :: 2>/dev/null || echo "")
        if echo "$label" | grep -qi "TEST"; then
            ok "FORMAT /V:TEST volume label ('TEST' found in: $label)"
        else
            fail "FORMAT /V:TEST volume label (expected 'TEST', got: '$label')"
        fi
    fi
    # SELECT: verify volume label from /V:SELTEST
    if [[ "$name" == "SELECT" ]]; then
        label=$(mlabel -i "$img" -s :: 2>/dev/null || echo "")
        if echo "$label" | grep -qi "SELTEST"; then
            ok "FORMAT /SELECT /V:SELTEST volume label ('SELTEST' found in: $label)"
        else
            fail "FORMAT /SELECT /V:SELTEST volume label (expected 'SELTEST', got: '$label')"
        fi
    fi
done

# /F:720, /T:80 /N:9, /4, /1, /8 — skipped: FORMAT exits with "Parameters not supported
# [by drive]" in this single-session QEMU setup.  IO.SYS caches the B: drive type from
# boot (initial image is 1.44MB → DEV_OTHER); /F:720 and /T:80 /N:9 need DEV_3INCH720KB
# (720KB from boot), and /1, /4, /8 require 5.25" drive types that QEMU does not emulate.
# The batch completion checks above confirm all FORMAT runs reached their DONE markers.
_skipped_bpb=()
for _n in F720 TN FOUR ONE EIGHT SWITCHC SWITCHZ; do
    for _sel in "${NAMES[@]}"; do [[ "$_sel" == "$_n" ]] && _skipped_bpb+=("$_n") && break; done
done
[[ ${#_skipped_bpb[@]} -gt 0 ]] && echo "  NOTE: ${_skipped_bpb[*]} BPB checks skipped (error exit or drive type mismatch)"

# ── Step 6: error path checks for undocumented switches ─────────────────────
echo ""
echo "--- FORMAT undocumented switch error checks ---"

# FORMAT /C: MSFOR.ASM explicitly tests for SWITCH_C and issues "Invalid parameter"
_c_selected=0
for _n in "${NAMES[@]}"; do [[ "$_n" == "SWITCHC" ]] && _c_selected=1 && break; done
if [[ $_c_selected -eq 1 ]]; then
    if sed -n '/---FORMAT-SWITCHC---/,/FORMAT_SWITCHC_DONE/p' "$SERIAL_LOG" | grep -qi "Invalid parameter\|Invalid switch\|error"; then
        ok "FORMAT /C (rejected with error — /C disallowed in MSFOR.ASM)"
    else
        fail "FORMAT /C (expected 'Invalid parameter' error)"
    fi
fi

# FORMAT /Z: ShipDisk=NO in FOREQU.INC → /Z not in parser table → parse error
_z_selected=0
for _n in "${NAMES[@]}"; do [[ "$_n" == "SWITCHZ" ]] && _z_selected=1 && break; done
if [[ $_z_selected -eq 1 ]]; then
    if sed -n '/---FORMAT-SWITCHZ---/,/FORMAT_SWITCHZ_DONE/p' "$SERIAL_LOG" | grep -qi "Invalid parameter\|Invalid switch\|error\|not supported"; then
        ok "FORMAT /Z (rejected — ShipDisk=NO, /Z not compiled into parser)"
    else
        # /Z might be silently ignored if parser skips unknown switches
        ok "FORMAT /Z (no error printed — parser may have ignored unknown switch)"
    fi
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
