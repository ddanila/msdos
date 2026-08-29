#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/out"
FLOPPY="${FLOPPY_IMAGE:-$OUT/floppy.img}"

SELECTED_VARIANTS=("$@")
RUN_2880_SEPARATELY=0

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

trap 'kill ${QEMU_PID:-} 2>/dev/null; rm -f "$SERIAL_IN" "$SERIAL_OUT" "$QMP_SOCK" 2>/dev/null; [[ "$WORKDIR" != "$OUT" && "${KEEP_FORMAT_WORKDIR:-0}" != 1 ]] && rm -rf "$WORKDIR" 2>/dev/null; true' EXIT

echo "=== FORMAT E2E tests (QEMU, QMP disk swapping) ==="

NAMES=("VLABEL" "Q"      "U"      "S"      "B"      "F720"   "F2880"  "TN"     "FOUR"   "ONE"    "EIGHT"
       "SWITCHC" "SWITCHZ" "SELECT" "AUTOTEST" "BACKUP")
FORMAT_CMDS=(
    "FORMAT B: /V:TEST"
    "FORMAT B: /Q /V:QUICK"
    "FORMAT B: /U /V:UNCOND"
    "FORMAT B: /S"
    "FORMAT B: /B"
    "FORMAT B: /F:720"
    "FORMAT B: /F:2.88"
    "FORMAT B: /T:80 /N:9"
    "FORMAT B: /4"
    "FORMAT B: /4 /1"
    "FORMAT B: /8"
    "FORMAT B: /C"
    "FORMAT B: /Z"
    "FORMAT B: /SELECT /V:SELTEST"
    "FORMAT B: /AUTOTEST /V:AUTO"
    "FORMAT B: /BACKUP /V:BKP"
)
B_SECTORS=(2880 2880 2880 2880 2880 1440 5760 1440 2400 2400 720
           2880 2880 2880 2880 2880)
NO_LABEL_NAMES=(VLABEL Q U EIGHT SELECT AUTOTEST BACKUP)

if [[ ${#SELECTED_VARIANTS[@]} -eq 0 && "${FORMAT_2880_CHILD:-0}" != 1 ]]; then
    # QEMU fixes the emulated floppy-drive type at boot.  Exercise 2.88 MB
    # media in its own VM instead of hot-swapping it into a 1.44 MB drive.
    RUN_2880_SEPARATELY=1
    SELECTED_VARIANTS=(VLABEL Q U S B F720 TN FOUR ONE EIGHT SWITCHC SWITCHZ SELECT AUTOTEST BACKUP)
fi

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

echo "Building test images..."
cp "$FLOPPY" "$BOOT_IMG"
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    for i in "${!NAMES[@]}"; do
        printf 'ECHO ---FORMAT-%s---\r\n' "${NAMES[$i]}"
        printf '%s\r\n' "${FORMAT_CMDS[$i]}"
        case "${NAMES[$i]}" in
            TN|SWITCHC|SWITCHZ)
                printf 'IF ERRORLEVEL 1 ECHO FORMAT_%s_NONZERO\r\n' "${NAMES[$i]}"
                ;;
        esac
        printf 'ECHO FORMAT_%s_DONE\r\n' "${NAMES[$i]}"
    done
    printf 'ECHO ===DONE===\r\n'
} | mcopy -o -i "$BOOT_IMG" - ::AUTOEXEC.BAT

if [[ "${NAMES[0]}" == "F720" ]]; then
    printf 'DRIVPARM=/D:1 /F:2\r\n' | mcopy -o -i "$BOOT_IMG" - ::CONFIG.SYS
fi

for i in "${!NAMES[@]}"; do
    B_IMGS+=("$OUT/format-b-${NAMES[$i]}.img")
    SAVED_IMGS+=("$OUT/format-saved-${NAMES[$i]}.img")
    dd if=/dev/zero bs=512 count="${B_SECTORS[$i]}" of="${B_IMGS[$i]}" status=none
    if [[ "${NAMES[$i]}" == "VLABEL" || "${NAMES[$i]}" == "Q" || "${NAMES[$i]}" == "U" ]]; then
        mformat -i "${B_IMGS[$i]}" ::
        printf '%s-format-marker\r\n' "${NAMES[$i]}" | mcopy -i "${B_IMGS[$i]}" - ::MARKER.TXT
    fi
done

mkfifo "$SERIAL_IN" "$SERIAL_OUT"
# Holding the input FIFO as O_RDWR prevents either endpoint from blocking during startup.
exec 3<>"$SERIAL_IN"

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

_NAMES_CSV=$(IFS=,; echo "${NAMES[*]}")
_NO_LABEL_CSV=$(IFS=,; echo "${NO_LABEL_NAMES[*]}")
python3 "$REPO_ROOT/tests/format_coordinator.py" \
    "$SERIAL_IN" "$SERIAL_OUT" "$SERIAL_LOG" "$QMP_SOCK" \
    "${#NAMES[@]}" "$_NAMES_CSV" "$_NO_LABEL_CSV" \
    "${B_IMGS[@]}" \
    "${SAVED_IMGS[@]}"

kill $QEMU_PID 2>/dev/null || true
wait $QEMU_PID || true
exec 3>&-

if [[ ! -f "$SERIAL_LOG" || ! -s "$SERIAL_LOG" ]]; then
    echo "ERROR: serial log is empty — QEMU may have failed to boot"
    exit 1
fi

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
_full_count=0
for _fn in VLABEL Q U S B F720 F2880 FOUR ONE EIGHT BACKUP; do
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

for i in "${!NAMES[@]}"; do
    name="${NAMES[$i]}"
    case "$name" in
        VLABEL|Q|U|S|B|SELECT|AUTOTEST|BACKUP) es=18; eh=2; et=2880 ;;
        F720) es=9; eh=2; et=1440 ;;
        F2880) es=36; eh=2; et=5760 ;;
        FOUR) es=9; eh=2; et=720 ;;
        ONE) es=9; eh=1; et=360 ;;
        EIGHT) continue ;;
        *) continue ;;
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
    if [[ "$name" == "VLABEL" ]]; then
        label=$(mlabel -i "$img" -s :: 2>/dev/null || echo "")
        if echo "$label" | grep -qi "TEST"; then
            ok "FORMAT /V:TEST volume label ('TEST' found in: $label)"
        else
            fail "FORMAT /V:TEST volume label (expected 'TEST', got: '$label')"
        fi
        if ! mdir -i "$img" ::MARKER.TXT >/dev/null 2>&1 \
            && grep -a -q 'VLABEL-format-marker' "$img"; then
            ok "FORMAT safe default verifies media without overwriting file data"
        else
            fail "FORMAT safe-default data preservation"
        fi
    fi
    if [[ "$name" == "Q" ]]; then
        if ! mdir -i "$img" ::MARKER.TXT >/dev/null 2>&1 \
            && grep -a -q 'Q-format-marker' "$img"; then
            ok "FORMAT /Q clears metadata without overwriting file data"
        else
            fail "FORMAT /Q metadata-only behavior"
        fi
    fi
    if [[ "$name" == "U" ]]; then
        if ! mdir -i "$img" ::MARKER.TXT >/dev/null 2>&1; then
            ok "FORMAT /U removes all DOS-visible prior data"
        else
            fail "FORMAT /U left prior directory data visible"
        fi
    fi
    if [[ "$name" == "SELECT" ]]; then
        label=$(mlabel -i "$img" -s :: 2>/dev/null || echo "")
        if echo "$label" | grep -qi "SELTEST"; then
            ok "FORMAT /SELECT /V:SELTEST volume label ('SELTEST' found in: $label)"
        else
            fail "FORMAT /SELECT /V:SELTEST volume label (expected 'SELTEST', got: '$label')"
        fi
    fi
    if [[ "$name" == "BACKUP" ]]; then
        label=$(mlabel -i "$img" -s :: 2>/dev/null || echo "")
        if echo "$label" | grep -qi "BKP"; then
            ok "FORMAT /BACKUP /V:BKP suppresses insertion prompt and writes exact label"
        else
            fail "FORMAT /BACKUP /V:BKP (expected BKP label, got: '$label')"
        fi
    fi
    if [[ "$name" == "AUTOTEST" ]]; then
        label=$(mlabel -i "$img" -s :: 2>/dev/null || echo "")
        if echo "$label" | grep -qi "no label"; then
            ok "FORMAT /AUTOTEST /V:AUTO leaves the unattended disk unlabeled"
        else
            fail "FORMAT /AUTOTEST /V:AUTO (expected no label, got: '$label')"
        fi
    fi
done

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

_tn_selected=0
for _n in "${NAMES[@]}"; do [[ "$_n" == "TN" ]] && _tn_selected=1 && break; done
if [[ $_tn_selected -eq 1 ]]; then
    if sed -n '/---FORMAT-TN---/,/FORMAT_TN_DONE/p' "$SERIAL_LOG" | grep -qi "Parameters not supported" \
        && grep -q 'FORMAT_TN_NONZERO' "$SERIAL_LOG"; then
        ok "FORMAT /T:80 /N:9 (drive-specific rejection asserted)"
    else
        fail "FORMAT /T:80 /N:9 (expected drive-specific rejection)"
    fi
fi

echo ""
echo "--- FORMAT undocumented switch error checks ---"

_c_selected=0
for _n in "${NAMES[@]}"; do [[ "$_n" == "SWITCHC" ]] && _c_selected=1 && break; done
if [[ $_c_selected -eq 1 ]]; then
    if sed -n '/---FORMAT-SWITCHC---/,/FORMAT_SWITCHC_DONE/p' "$SERIAL_LOG" | grep -q 'Invalid switch - /C' \
        && ! grep -q 'FORMAT_SWITCHC_NONZERO' "$SERIAL_LOG"; then
        ok "FORMAT /C prints its exact rejection and preserves historical zero status"
    else
        fail "FORMAT /C diagnostic or status contract"
    fi
fi

_z_selected=0
for _n in "${NAMES[@]}"; do [[ "$_n" == "SWITCHZ" ]] && _z_selected=1 && break; done
if [[ $_z_selected -eq 1 ]]; then
    if sed -n '/---FORMAT-SWITCHZ---/,/FORMAT_SWITCHZ_DONE/p' "$SERIAL_LOG" | grep -q 'Invalid switch - /Z' \
        && ! grep -q 'FORMAT_SWITCHZ_NONZERO' "$SERIAL_LOG"; then
        ok "FORMAT /Z prints its exact rejection and preserves historical zero status"
    else
        fail "FORMAT /Z diagnostic or status contract"
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

if [[ $FAIL -eq 0 && $RUN_2880_SEPARATELY -eq 1 ]]; then
    FORMAT_2880_CHILD=1 FORMAT_WORKDIR="$OUT/format-2880-work" \
        bash "$0" F2880 || FAIL=$((FAIL+1))
fi

[[ $FAIL -eq 0 ]]
