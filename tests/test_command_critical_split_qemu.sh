#!/usr/bin/env bash
# Build the development body boundary without changing production objects/media.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export MTOOLS_SKIP_CHECK=1 MTOOLS_NO_VFAT=1
work=$(mktemp -d "$ROOT/out/command-critical-split.XXXXXX")
echo "Critical split artifacts: $work"
cp "$ROOT/src/CMD/COMMAND/"*.OBJ "$work/"
cp "$ROOT/src/CMD/COMMAND/COMMAND.LNK" "$work/"
(
    cd "$ROOT/src/CMD/COMMAND"
    for module in RUCODE INIT; do
        "$ROOT/bin/jwasm-masm" \
            "-Mx -t -DCOMMAND_CRITICAL_SPLIT -I. -I../../INC -I../../DOS -Fl=$work/$module.LST" \
            "$module.ASM,$work/$module.OBJ;"
    done
)
(
    cd "$work"
    "$ROOT/bin/wlink" '@COMMAND.LNK'
    "$ROOT/bin/exe2bin" 'COMMAND.EXE COMMAND.COM'
)
python3 "$ROOT/tests/report_command_residency.py" --check --critical-split \
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
