#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C MTOOLS_SKIP_CHECK=1

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/tests/86box_286_lib.sh"

for tool in nasm mcopy mformat mtype python3; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done
check_86box_286_prerequisites || exit $?

work=$(mktemp -d "${TMPDIR:-/tmp}/msdos-pre386-memory.XXXXXX")
trap 'rm -rf "$work"' EXIT
image="$work/pre386-memory.img"

nasm -DCHECK_EMM_DEVICE -f bin "$ROOT/tests/pre386_fallback_probe.asm" \
    -o "$work/PRE386.COM"
nasm -f bin "$ROOT/tests/devicehigh_reference_driver.asm" -o "$work/DHREF.SYS"
nasm -DEXPECT_HIGH=0 -f bin "$ROOT/tests/devicehigh_state_probe.asm" \
    -o "$work/DHSTATE.COM"
nasm -f bin "$ROOT/tests/loadhigh_child.asm" -o "$work/LHCHILD.COM"
make_86box_286_boot_image "$image" "$ROOT"
for artifact in HIMEM.SYS EMM386.EXE MEMMAKER.EXE FC.EXE FIND.EXE; do
    case $artifact in
        HIMEM.SYS) source_file="$ROOT/src/DEV/HIMEM/HIMEM.SYS" ;;
        EMM386.EXE) source_file="$ROOT/src/MEMM/MEMM/EMM386.EXE" ;;
        MEMMAKER.EXE) source_file="$ROOT/src/CMD/MEMMAKER/MEMMAKER.EXE" ;;
        FC.EXE) source_file="$ROOT/src/CMD/FC/FC.EXE" ;;
        FIND.EXE) source_file="$ROOT/src/CMD/FIND/FIND.EXE" ;;
    esac
    mcopy -o -i "$image" "$source_file" "::$artifact"
done
mcopy -o -i "$image" "$work/PRE386.COM" ::PRE386.COM
mcopy -o -i "$image" "$work/DHREF.SYS" ::DHREF.SYS
mcopy -o -i "$image" "$work/DHSTATE.COM" ::DHSTATE.COM
mcopy -o -i "$image" "$work/LHCHILD.COM" ::LHCHILD.COM
write_config() {
    printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\r\n'
    printf 'DEVICE=A:\\EMM386.EXE NOEMS\r\n'
    printf 'DOS=HIGH,UMB\r\n'
    printf 'DEVICEHIGH=A:\\DHREF.SYS FALLBACK\r\n'
}
write_config | mcopy -o -i "$image" - ::CONFIG.SYS
write_config | mcopy -o -i "$image" - ::CONFIG.REF
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'PRE386.COM >PRE386.TXT\r\n'
    printf 'IF ERRORLEVEL 1 GOTO FAIL\r\n'
    printf 'FIND "PRE386_FALLBACK_PASS" PRE386.TXT >NUL\r\n'
    printf 'IF ERRORLEVEL 1 GOTO FAIL\r\n'
    printf 'DHSTATE.COM >DHSTATE.TXT\r\n'
    printf 'FIND "DEVICEHIGH_FALLBACK_PASS" DHSTATE.TXT >NUL\r\n'
    printf 'IF ERRORLEVEL 1 GOTO FAIL\r\n'
    printf 'LOADHIGH LHCHILD.COM >LH.TXT\r\n'
    printf 'IF ERRORLEVEL 1 GOTO FAIL\r\n'
    printf 'FIND "LOADHIGH_CHILD_END" LH.TXT >NUL\r\n'
    printf 'IF ERRORLEVEL 1 GOTO FAIL\r\n'
    printf 'MEMMAKER /BATCH\r\n'
    printf 'IF NOT ERRORLEVEL 1 GOTO FAIL\r\n'
    printf 'IF EXIST CONFIG.MM GOTO FAIL\r\n'
    printf 'IF EXIST AUTOEXEC.MM GOTO FAIL\r\n'
    printf 'FC /B CONFIG.SYS CONFIG.REF >FC.TXT\r\n'
    printf 'FIND "no differences encountered" FC.TXT >NUL\r\n'
    printf 'IF ERRORLEVEL 1 GOTO FAIL\r\n'
    printf 'ECHO 86BOX_PRE386_MEMORY_PASS>RESULT.TXT\r\n'
    printf 'TYPE RESULT.TXT\r\n'
    printf 'GOTO WAIT\r\n'
    printf ':FAIL\r\n'
    printf 'ECHO 86BOX_PRE386_MEMORY_PRODUCT_FAIL>RESULT.TXT\r\n'
    printf 'TYPE RESULT.TXT\r\n'
    printf ':WAIT\r\n'
    printf 'GOTO WAIT\r\n'
} | mcopy -o -i "$image" - ::AUTOEXEC.BAT

run_86box_286 "$image" 86BOX_PRE386_MEMORY_PASS \
    86BOX_PRE386_MEMORY_PRODUCT_FAIL "${BOX86_TIMEOUT:-180}" "$ROOT" >/dev/null
echo '  PASS: EMM386 rejection and DEVICEHIGH/LOADHIGH/MemMaker 286 fallback'
