#!/usr/bin/env bash
# Build the development body boundary without changing production objects/media.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export MTOOLS_SKIP_CHECK=1 MTOOLS_NO_VFAT=1
reclaim=${COMMAND_CRITICAL_RECLAIM:-0}
[[ "$reclaim" == 0 || "$reclaim" == 1 ]] || exit 1
reclaim_define=""
if [[ "$reclaim" == 1 ]]; then reclaim_define=-DCOMMAND_CRITICAL_RECLAIM; fi
work=$(mktemp -d "$ROOT/out/command-critical-split.XXXXXX")
echo "Critical split artifacts: $work"
cp "$ROOT/src/CMD/COMMAND/"*.OBJ "$work/"
cp "$ROOT/src/CMD/COMMAND/COMMAND.LNK" "$work/"
(
    cd "$ROOT/src/CMD/COMMAND"
    for module in RUCODE INIT; do
        "$ROOT/bin/jwasm-masm" \
            "-Mx -t -DCOMMAND_CRITICAL_SPLIT $reclaim_define -I. -I../../INC -I../../DOS -Fl=$work/$module.LST" \
            "$module.ASM,$work/$module.OBJ;"
    done
)
(
    cd "$work"
    "$ROOT/bin/wlink" '@COMMAND.LNK'
    "$ROOT/bin/exe2bin" 'COMMAND.EXE COMMAND.COM'
)
report_options=(--critical-split)
if [[ "$reclaim" == 1 ]]; then report_options+=(--critical-reclaim); fi
python3 "$ROOT/tests/report_command_residency.py" --check "${report_options[@]}" \
    --switches "$ROOT/src/CMD/COMMAND/comsw.asm" \
    "$work/COMMAND.MAP" "$work/COMMAND.COM" > "$work/residency.md"
cp "$ROOT/out/floppy.img" "$work/floppy.img"
mcopy -o -i "$work/floppy.img" "$work/COMMAND.COM" ::COMMAND.COM
map_offset() {
    local value
    value=$(awk -v name="$1" 'toupper($2)==toupper(name) {
        split($1,a,":"); sub(/\*$/, "", a[2]); print a[2]; exit
    }' "$work/COMMAND.MAP")
    [[ "$value" =~ ^[0-9A-Fa-f]{4}$ ]] || return 1
    printf '0x%s' "$value"
}
if [[ "$reclaim" == 1 ]]; then
    low_paras=$(( ($(map_offset resident_catalog_start) + 15) / 16 ))
    nasm -DEXPECT_HIGH "-DEXPECTED_LOW_PARAS=$low_paras" \
        "-DBODY_START=$(map_offset critical_body_start)" \
        "-DDISPATCH_OFFSET=$(map_offset critical_dispatch)" -f bin \
        "$ROOT/tests/command_critical_reclaim_probe.asm" -o "$work/CRITMEM.COM"
    normal_end=$(awk 'toupper($2)=="RESIDENT_CATALOG_START" {
        split($1,a,":"); print a[2]; exit
    }' "$ROOT/src/CMD/COMMAND/COMMAND.MAP")
    [[ "$normal_end" =~ ^[0-9A-Fa-f]{4}$ ]] || exit 1
    normal_paras=$(( (16#$normal_end + 15) / 16 ))
    nasm "-DEXPECTED_LOW_PARAS=$normal_paras" -f bin \
        "$ROOT/tests/command_critical_reclaim_probe.asm" -o "$work/BASEMEM.COM"
    COMMAND_CRITICAL_ABI=1 COMMAND_CRITICAL_RECLAIM_PROBE="$work/BASEMEM.COM" \
        bash "$ROOT/tests/test_command_startup_qemu.sh" > "$work/baseline.log" 2>&1
    cp "$ROOT/out/command-fail-serial.log" "$work/baseline-serial.log"
    for action in fail retry; do
        FLOPPY_IMAGE="$work/floppy.img" COMMAND_CRITICAL_ABI=1 \
            COMMAND_CRITICAL_RECLAIM_PROBE="$work/CRITMEM.COM" \
            COMMAND_CRITICAL_ACTION="$action" \
            bash "$ROOT/tests/test_command_startup_qemu.sh" > "$work/reclaim-$action.log" 2>&1
        cp "$ROOT/out/command-fail-serial.log" "$work/reclaim-$action-serial.log"
        expected=$(( (normal_paras - low_paras) * 16 ))
        for phase in 1 2; do
            baseline=$(sed -n 's/^COMMAND_CRITICAL_LARGEST=//p' "$work/baseline-serial.log" | sed -n "${phase}p" | tr -d '\r')
            largest=$(sed -n 's/^COMMAND_CRITICAL_LARGEST=//p' "$work/reclaim-$action-serial.log" | sed -n "${phase}p" | tr -d '\r')
            [[ "$baseline" =~ ^[0-9A-Fa-f]{4}$ && "$largest" =~ ^[0-9A-Fa-f]{4}$ ]] || exit 1
            gain=$(( (16#$largest - 16#$baseline) * 16 ))
            if (( gain != expected || gain <= 0 )); then
                echo "FAIL: phase $phase largest-block gain $gain, parent release $expected"
                exit 1
            fi
        done
        echo "PASS: startup high/$action; $gain bytes coalesced into largest block"
    done
    for fallback in msg dos-low hma-full; do
        mode=HIGH
        messages=resident
        buffers=""
        extra_defines=(-DEXPECT_LOW)
        fallback_end=$(map_offset extmsgend)
        if [[ "$fallback" == dos-low ]]; then
            mode=LOW
            messages=disk
            fallback_end=$(map_offset hma_code_end)
        fi
        if [[ "$fallback" == hma-full ]]; then
            messages=disk
            buffers=46
            fallback_end=$(map_offset hma_code_end)
            payload=$(( $(map_offset dataresend) - $(map_offset resident_catalog_start)
                        + $(map_offset hma_code_end) - $(map_offset hma_code_start) ))
            extra_defines+=(-DEXPECT_HMA_SHORTAGE "-DHMA_PAYLOAD_BYTES=$payload")
        fi
        fallback_paras=$(( (fallback_end + 15) / 16 ))
        nasm "${extra_defines[@]}" "-DEXPECTED_LOW_PARAS=$fallback_paras" \
            "-DBODY_START=$(map_offset critical_body_start)" \
            "-DBODY_END=$(map_offset critical_body_end)" \
            "-DDISPATCH_OFFSET=$(map_offset critical_dispatch)" -f bin \
            "$ROOT/tests/command_critical_reclaim_probe.asm" -o "$work/FALLBACK.COM"
        FLOPPY_IMAGE="$work/floppy.img" COMMAND_CRITICAL_ABI=1 \
            COMMAND_CRITICAL_RECLAIM_PROBE="$work/FALLBACK.COM" \
            COMMAND_CRITICAL_MESSAGES="$messages" COMMAND_CRITICAL_DOS_MODE="$mode" \
            COMMAND_CRITICAL_BUFFERS="$buffers" \
            bash "$ROOT/tests/test_command_startup_qemu.sh" > "$work/$fallback.log" 2>&1
        cp "$ROOT/out/command-fail-serial.log" "$work/$fallback-serial.log"
        echo "PASS: retained $fallback body and low dispatch"
    done
    exit 0
fi
loader_defines=("-DBODY_START=$(map_offset critical_body_start)"
    "-DBODY_END=$(map_offset critical_body_end)"
    "-DDISPATCH_OFFSET=$(map_offset critical_dispatch)")
slot=0
for entry in CRLF RPRINT SYSGETMSG TestKanjR IN_CHAR_XLAT ResPipeOff int21 int2f return reload terminate dead; do
    loader_defines+=("-DSEGMENT_FIXUP_$slot=$(map_offset "critical_${entry}_segment")")
    slot=$((slot+1))
done
nasm "${loader_defines[@]}" -f bin "$ROOT/tests/command_critical_body_loader.asm" \
    -o "$work/CRITHIGH.COM"
for placement in low high; do
for action in fail retry; do
    loader=""
    if [[ "$placement" == high ]]; then loader="$work/CRITHIGH.COM"; fi
    FLOPPY_IMAGE="$work/floppy.img" COMMAND_CRITICAL_ABI=1 \
        COMMAND_CRITICAL_LOADER="$loader" \
        COMMAND_CRITICAL_ACTION="$action" \
        bash "$ROOT/tests/test_command_startup_qemu.sh" > "$work/$placement-$action.log" 2>&1 || {
            echo "FAIL: development critical $placement/$action; see $work/$placement-$action.log"
            exit 1
        }
    cp "$ROOT/out/command-fail-serial.log" "$work/$placement-$action-serial.log"
    echo "PASS: development critical $placement/$action"
done
done
