#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="${FLOPPY_IMAGE:-$ROOT/out/floppy.img}"
RUN=$(mktemp -d "$ROOT/out/command-resident-binding.XXXXXX")
echo "Evidence: $RUN"
for variant in normal binding; do
    build="$RUN/$variant"
    mkdir "$build"
    cp "$ROOT/src/CMD/COMMAND/"*.OBJ "$build/"
    cp "$ROOT/src/CMD/COMMAND/COMMAND.LNK" "$build/"
    define=""
    if [[ "$variant" == binding ]]; then define=-DCOMMAND_RESIDENT_BINDING; fi
    (
        cd "$ROOT/src/CMD/COMMAND"
        for module in COMMAND1 COMMAND2 RUCODE INIT; do
            "$ROOT/bin/jwasm-masm" \
                "-Mx -t $define -I. -I../../INC -I../../DOS -Fl=$build/$module.LST" \
                "$module.ASM,$build/$module.OBJ;"
        done
    )
    (
        cd "$build"
        "$ROOT/bin/wlink" '@COMMAND.LNK'
        "$ROOT/bin/exe2bin" 'COMMAND.EXE COMMAND.COM'
    )
done
cmp "$RUN/normal/COMMAND.COM" "$ROOT/src/CMD/COMMAND/COMMAND.COM"
echo 'PASS: default COMMAND binary unchanged'
python3 "$ROOT/tests/report_command_residency.py" --check --resident-binding \
    --binding-listings "$RUN/binding/COMMAND1.LST" "$RUN/binding/COMMAND2.LST" "$RUN/binding/RUCODE.LST" \
    --switches "$ROOT/src/CMD/COMMAND/comsw.asm" \
    "$RUN/binding/COMMAND.MAP" "$RUN/binding/COMMAND.COM" > "$RUN/residency.md"
FLOPPY_IMAGE="$INPUT" COMMAND_IMAGE="$RUN/binding/COMMAND.COM" \
    bash "$ROOT/tests/test_command_int2e_owner_qemu.sh"
cp "$INPUT" "$RUN/boot.img"
MTOOLS_SKIP_CHECK=1 MTOOLS_NO_VFAT=1 mcopy -o -i "$RUN/boot.img" \
    "$RUN/binding/COMMAND.COM" ::COMMAND.COM
FLOPPY_IMAGE="$RUN/boot.img" COMMAND_CRITICAL_ABI=1 \
    bash "$ROOT/tests/test_command_startup_qemu.sh" > "$RUN/startup.log" 2>&1
FLOPPY_IMAGE="$RUN/boot.img" \
    bash "$ROOT/tests/test_loadhigh_qemu.sh" > "$RUN/loadhigh.log" 2>&1
for name in provider regions fallback high; do
    cp "$ROOT/out/loadhigh-$name.log" "$RUN/loadhigh-$name.log"
done
echo "PASS: resident bindings, INT 2Eh, startup, critical ABI and LOADHIGH; $RUN"
