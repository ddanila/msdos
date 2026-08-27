#!/bin/bash
# tests/test_format.sh — E2E tests for FORMAT.COM via QEMU with QMP floppy swapping.
#
# Selected FORMAT variants run in one QEMU session. After each FORMAT the host:
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
#   /4 /1 (single-sided in 1.2MB)    : spt=9,  heads=1, total=360
#   /8 (8 sec/track on 360KB drive)  : legacy pre-BPB 320KB FAT12 layout
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

trap 'kill ${QEMU_PID:-} 2>/dev/null; rm -f "$SERIAL_IN" "$SERIAL_OUT" "$QMP_SOCK" 2>/dev/null; [[ "$WORKDIR" != "$OUT" ]] && rm -rf "$WORKDIR" 2>/dev/null; true' EXIT

echo "=== FORMAT E2E tests (QEMU, QMP disk swapping) ==="

# ── Test definitions ──────────────────────────────────────────────────────────
# NAMES must be uppercase (used verbatim in AUTOEXEC.BAT ECHO markers).
# B_SECTORS also selects QEMU's initial B: drive geometry. CI groups variants
# by the drive type cached by IO.SYS: DRIVPARM supplies a 720KB B: for F720/TN,
# a 1.2MB image backs FOUR/ONE, and a 360KB image backs EIGHT. /C and /Z exit
# with "Invalid parameter" (error paths).
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
    "FORMAT B: /4 /1"
    "FORMAT B: /8"
    "FORMAT B: /C"
    "FORMAT B: /Z"
    "FORMAT B: /SELECT /V:SELTEST"
    "FORMAT B: /AUTOTEST /V:AUTO"
)
B_SECTORS=(2880 2880 2880 1440 1440 2400 2400 720
           2880 2880 2880 2880)
# Which NAMES have /V:<label> on the command line → FORMAT skips volume-label prompt.
NO_LABEL_NAMES=(VLABEL EIGHT SELECT AUTOTEST)

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
        case "${NAMES[$i]}" in
            TN|SWITCHC|SWITCHZ)
                printf 'IF ERRORLEVEL 1 ECHO FORMAT_%s_REJECTED\r\n' "${NAMES[$i]}"
                ;;
        esac
        printf 'ECHO FORMAT_%s_DONE\r\n' "${NAMES[$i]}"
    done
    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

# QEMU exposes a 1.44MB floppy drive for 3.5-inch media regardless of the
# inserted image size. Override DOS's cached B: geometry for the two 720KB
# variants so FORMAT exercises their success path on the matching drive type.
if [[ "${NAMES[0]}" == "F720" ]]; then
    printf 'DRIVPARM=/D:1 /F:2\r\n' | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
fi

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
# Count variants expected to complete an actual format.
_full_count=0
for _fn in VLABEL S B F720 FOUR ONE EIGHT; do
    for _n in "${NAMES[@]}"; do [[ "$_n" == "$_fn" ]] && _full_count=$((_full_count+1)) && break; done
done
if [[ $_full_count -gt 0 ]]; then
    count=$(grep -ic "Format complete" "$SERIAL_LOG" || true)
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

# Expected BPB geometry per variant name. Error-only variants are omitted.
# Keep this compatible with macOS's system Bash 3.2 (no associative arrays).
for i in "${!NAMES[@]}"; do
    name="${NAMES[$i]}"
    case "$name" in
        VLABEL|S|B|SELECT|AUTOTEST) es=18; eh=2; et=2880 ;;
        F720) es=9; eh=2; et=1440 ;;
        FOUR) es=9; eh=2; et=720 ;;
        ONE) es=9; eh=1; et=360 ;;
        EIGHT) continue ;;                     # checked as a legacy layout below
        *) continue ;;                         # error-only variant
    esac
    img="${SAVED_IMGS[$i]}"
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
    # AUTOTEST is an unattended factory path: it suppresses normal completion
    # output and intentionally leaves the disk unlabeled despite /V:AUTO.
    if [[ "$name" == "AUTOTEST" ]]; then
        label=$(mlabel -i "$img" -s :: 2>/dev/null || echo "")
        if echo "$label" | grep -qi "no label"; then
            ok "FORMAT /AUTOTEST /V:AUTO leaves the unattended disk unlabeled"
        else
            fail "FORMAT /AUTOTEST /V:AUTO (expected no label, got: '$label')"
        fi
    fi
done

# /8 deliberately selects FORMAT's old-directory layout. Its boot sector
# predates the DOS 2 BPB, so zero BPB fields are correct; validate the legacy
# boot signature, both FAT media bytes, root marker, and usable capacity.
_eight_selected=0
for _n in "${NAMES[@]}"; do [[ "$_n" == "EIGHT" ]] && _eight_selected=1 && break; done
if [[ $_eight_selected -eq 1 ]]; then
    eight_img=""
    for i in "${!NAMES[@]}"; do
        [[ "${NAMES[$i]}" == "EIGHT" ]] && eight_img="${SAVED_IMGS[$i]}" && break
    done
    legacy=$(python3 - "$eight_img" <<'PYEOF'
import sys
with open(sys.argv[1], 'rb') as f:
    image = f.read()
print(f"boot={image[:3].hex()} bpb={image[11:13].hex()} "
      f"fat1={image[512]:02x} fat2={image[1024]:02x} root={image[1536]:02x}")
PYEOF
)
    free_bytes=$(mdir -i "$eight_img" :: 2>/dev/null | sed -n 's/[^0-9]*\([0-9][0-9 ]*[0-9]\) bytes free.*/\1/p' | tr -d ' ')
    if [[ "$legacy" == "boot=eb2790 bpb=0000 fat1=ff fat2=ff root=e5" && "$free_bytes" == "322560" ]]; then
        ok "FORMAT /8 legacy 320KB FAT12 layout ($legacy, free=$free_bytes)"
    else
        fail "FORMAT /8 legacy layout: got '$legacy', free='${free_bytes:-missing}'"
    fi
fi

# On the 720KB DRIVPARM geometry used by the F720/TN group, the explicit
# /T:80 /N:9 spelling reaches FORMAT's drive-specific rejection path. Assert
# that exact behavior rather than treating the absent BPB as a skipped check.
_tn_selected=0
for _n in "${NAMES[@]}"; do [[ "$_n" == "TN" ]] && _tn_selected=1 && break; done
if [[ $_tn_selected -eq 1 ]]; then
    if sed -n '/---FORMAT-TN---/,/FORMAT_TN_DONE/p' "$SERIAL_LOG" | grep -qi "Parameters not supported" \
        && grep -q 'FORMAT_TN_REJECTED' "$SERIAL_LOG"; then
        ok "FORMAT /T:80 /N:9 (drive-specific rejection asserted)"
    else
        fail "FORMAT /T:80 /N:9 (expected drive-specific rejection)"
    fi
fi

# ── Step 6: error path checks for undocumented switches ─────────────────────
echo ""
echo "--- FORMAT undocumented switch error checks ---"

# FORMAT /C: MSFOR.ASM explicitly tests for SWITCH_C and issues "Invalid parameter"
_c_selected=0
for _n in "${NAMES[@]}"; do [[ "$_n" == "SWITCHC" ]] && _c_selected=1 && break; done
if [[ $_c_selected -eq 1 ]]; then
    if sed -n '/---FORMAT-SWITCHC---/,/FORMAT_SWITCHC_DONE/p' "$SERIAL_LOG" | grep -qi "Invalid parameter\|Invalid switch\|error" \
        && grep -q 'FORMAT_SWITCHC_REJECTED' "$SERIAL_LOG"; then
        ok "FORMAT /C (rejected with error — /C disallowed in MSFOR.ASM)"
    else
        fail "FORMAT /C (expected 'Invalid parameter' error)"
    fi
fi

# FORMAT /Z: ShipDisk=NO in FOREQU.INC → /Z not in parser table → parse error
_z_selected=0
for _n in "${NAMES[@]}"; do [[ "$_n" == "SWITCHZ" ]] && _z_selected=1 && break; done
if [[ $_z_selected -eq 1 ]]; then
    if sed -n '/---FORMAT-SWITCHZ---/,/FORMAT_SWITCHZ_DONE/p' "$SERIAL_LOG" | grep -qi "Invalid parameter\|Invalid switch\|error\|not supported" \
        && grep -q 'FORMAT_SWITCHZ_REJECTED' "$SERIAL_LOG"; then
        ok "FORMAT /Z (rejected — ShipDisk=NO, /Z not compiled into parser)"
    else
        fail "FORMAT /Z (expected parser rejection)"
    fi
fi

for rejected_name in TN SWITCHC SWITCHZ; do
    for i in "${!NAMES[@]}"; do
        [[ "${NAMES[$i]}" == "$rejected_name" ]] || continue
        if python3 - "${SAVED_IMGS[$i]}" <<'PYEOF'
import sys
image = open(sys.argv[1], 'rb').read()
assert image and not any(image)
PYEOF
        then
            ok "FORMAT $rejected_name left every target byte unchanged"
        else
            fail "FORMAT $rejected_name modified rejected target media"
        fi
    done
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
