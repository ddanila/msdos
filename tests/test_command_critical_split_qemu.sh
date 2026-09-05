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
    "$ROOT/bin/jwasm-masm" \
        "-Mx -t -DCOMMAND_CRITICAL_SPLIT -I. -I../../INC -I../../DOS -Fl=$work/RUCODE.LST" \
        "RUCODE.ASM,$work/RUCODE.OBJ;"
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
for action in fail retry; do
    FLOPPY_IMAGE="$work/floppy.img" COMMAND_CRITICAL_ABI=1 \
        COMMAND_CRITICAL_ACTION="$action" \
        bash "$ROOT/tests/test_command_startup_qemu.sh" > "$work/$action.log" 2>&1 || {
            echo "FAIL: development critical $action; see $work/$action.log"
            exit 1
        }
    cp "$ROOT/out/command-fail-serial.log" "$work/$action-serial.log"
    echo "PASS: development critical $action"
done
