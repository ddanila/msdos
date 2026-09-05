#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
FLOPPY="$OUT/floppy.img"
HIMEM="$OUT/mem-umb-himem.sys"
STATE="$OUT/mem-umb-state.com"
QEXIT="$OUT/mem-umb-exit.com"

for tool in mcopy nasm qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done

mcopy -o -i "$FLOPPY" ::HIMEM.SYS "$HIMEM"
nasm -f bin "$ROOT/tests/loadhigh_state.asm" -o "$STATE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"

run_image() {
    local image=$1
    local log=$2

    timeout 35 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >"$log" 2>&1 || true
}

IMAGE="$OUT/mem-umb.img"
LOG="$OUT/mem-umb.log"
cp "$FLOPPY" "$IMAGE"
mcopy -o -i "$IMAGE" "$HIMEM" ::HIMEM.SYS
mcopy -o -i "$IMAGE" "$STATE" ::STATE.COM
mcopy -o -i "$IMAGE" "$QEXIT" ::QEXIT.COM
{
    printf 'DEVICE=HIMEM.SYS\r\n'
    printf 'DEVICE=EMM386.EXE RAM M5 I=CC00-CFFF I=E400-E7FF\r\n'
    printf 'DOS=HIGH,UMB\r\n'
} | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\n'
    printf 'ECHO MEM_SUMMARY_BEGIN\r\nMEM\r\n'
    printf 'ECHO MEM_CLASSIFY_BEGIN\r\nMEM /c\r\n'
    printf 'ECHO MEM_DEBUG_BEGIN\r\nMEM /D\r\n'
    printf 'ECHO MEM_FREE_BEGIN\r\nMEM /F\r\n'
    printf 'ECHO MEM_MODULE_BEGIN\r\nMEM /M COMMAND\r\n'
    printf 'ECHO MEM_DRIVER_MODULE_BEGIN\r\nMEM /M HIMEM\r\n'
    printf 'MEM /CLASSIFY > NUL\r\nIF ERRORLEVEL 1 ECHO MEM_SYNONYM_FAIL\r\n'
    printf 'MEM /FREE > NUL\r\nIF ERRORLEVEL 1 ECHO MEM_SYNONYM_FAIL\r\n'
    printf 'MEM /MODULE COMMAND > NUL\r\nIF ERRORLEVEL 1 ECHO MEM_SYNONYM_FAIL\r\n'
    printf 'MEM /M:COMMAND > NUL\r\nIF ERRORLEVEL 1 ECHO MEM_SYNONYM_FAIL\r\n'
    printf 'MEM /MODULE:COMMAND > NUL\r\nIF ERRORLEVEL 1 ECHO MEM_SYNONYM_FAIL\r\n'
    printf 'MEM /M MISSING\r\n'
    printf 'IF ERRORLEVEL 1 ECHO MEM_MISSING_PASS\r\n'
    printf 'STATE.COM\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT
run_image "$IMAGE" "$LOG"

for expected in \
    MEM_SUMMARY_BEGIN MEM_CLASSIFY_BEGIN MEM_DEBUG_BEGIN MEM_FREE_BEGIN \
    MEM_MODULE_BEGIN MEM_DRIVER_MODULE_BEGIN 'Modules using memory below 1 MB:' \
    'Memory Summary:' 'Largest free upper memory block' \
    'MS-DOS is resident in the high memory area.' \
    'Free Conventional Memory:' 'Free Upper Memory:' \
    'COMMAND is using the following memory:' \
    'HIMEM is using the following memory:' 'MEM_MISSING_PASS' 'LINK=0000'
do
    if ! grep -Fq "$expected" "$LOG"; then
        echo "FAIL: MEM UMB output missing: $expected" >&2
        strings -a "$LOG" | sed -n '1,260p' >&2
        exit 1
    fi
done

if grep -Fq 'MEM_SYNONYM_FAIL' "$LOG"; then
    echo 'FAIL: a MEM long or compact switch synonym failed' >&2
    strings -a "$LOG" | sed -n '1,260p' >&2
    exit 1
fi

# COMMAND reloads its transient half after startup. A stale low copy of
# SYSINIT's CDS pointer made the reload OPEN fail only after DOS reclaimed its
# relocation hole, even though the MCB chain itself remained structurally valid.
if grep -Fq 'Invalid COMMAND.COM' "$LOG" \
    || grep -Fq 'Cannot load COMMAND' "$LOG"
then
    echo 'FAIL: COMMAND could not reload after DOS-high arena reclamation' >&2
    strings -a "$LOG" | sed -n '1,180p' >&2
    exit 1
fi

# The normal 32-handle configuration must not retain capacity for all 128
# documented handles. Maximum-capacity behavior is covered separately.
himem_conventional=$(awk '$1 == "HIMEM" { print $3; exit }' "$LOG" | tr -d '\r')
if [[ ! "$himem_conventional" =~ ^[0-9]+$ ]] || (( himem_conventional > 3072 )); then
    echo 'FAIL: HIMEM exceeds the 3 KiB conventional-memory footprint budget' >&2
    echo "  HIMEM=${himem_conventional:-unparsed}" >&2
    strings -a "$LOG" | sed -n '1,180p' >&2
    exit 1
fi

# This fixed RAM configuration adds two explicit include regions to the default
# layout. Keep its live EMM386 payload at the measured 3,984-byte ceiling.
emm386_conventional=$(awk '$1 == "EMM386" { print $3; exit }' "$LOG" | tr -d '\r')
if [[ ! "$emm386_conventional" =~ ^[0-9]+$ ]] || (( emm386_conventional > 3984 )); then
    echo 'FAIL: EMM386 exceeds the 3,984-byte fixed-config footprint budget' >&2
    echo "  EMM386=${emm386_conventional:-unparsed}" >&2
    strings -a "$LOG" | sed -n '1,180p' >&2
    exit 1
fi

# DOS-high keeps the hash and normal cache slots in the HMA. Only the
# maximum-sector legacy-driver transfer area remains conventional.
buffers_conventional=$(tr -d '\r' < "$LOG" \
    | awk '$1 == "MSDOS" && $3 == "Config" && $4 == "B" { print $2; exit }')
if [[ "$buffers_conventional" != 512 ]]; then
    echo 'FAIL: DOS-high BUFFERS footprint is not the 512-byte transfer area' >&2
    echo "  BUFFERS=${buffers_conventional:-unparsed}" >&2
    strings -a "$LOG" | sed -n '1,180p' >&2
    exit 1
fi

if ! grep -Eq '^  Upper +49152 +48 +49104' "$LOG" \
    || ! grep -Eq '^  HIMEM +[1-9][0-9]* +[1-9][0-9]* +0' "$LOG" \
    || ! grep -Eq '^  EMM386 +[1-9][0-9]* +[1-9][0-9]* +0' "$LOG" \
    || ! grep -Eq '^  Free +[1-9][0-9]* +[1-9][0-9]* +[1-9][0-9]*' "$LOG" \
    || ! grep -Eq '^ +1 +16352 +16352 +16384' "$LOG" \
    || ! grep -Eq '^ +2 +32752 +32752 +32768' "$LOG" \
    || ! grep -Eq '^  CC00:0000 +FREE +16352 +Free +1' "$LOG" \
    || ! grep -Eq '^  CFFF:0000 +SYSTEM +65536 +System +1' "$LOG" \
    || ! grep -Eq '^  E000:0000 +FREE +32752 +Free +2' "$LOG"
then
    echo 'FAIL: MEM did not preserve exact split UMB region accounting' >&2
    strings -a "$LOG" | sed -n '1,260p' >&2
    exit 1
fi

# Measure the incremental low-memory cost of publishing UMBs.  Keep HIMEM,
# DOS=HIGH, the EMS page frame, and all machine settings identical; only RAM
# mode (and therefore the UMB map) differs.  The inherited EMM386 resident
# monitor is the baseline, not UMB overhead.
BUDGET_IMAGE="$OUT/mem-umb-budget-baseline.img"
BUDGET_LOG="$OUT/mem-umb-budget-baseline.log"
BUDGET_UMB_IMAGE="$OUT/mem-umb-budget-enabled.img"
BUDGET_UMB_LOG="$OUT/mem-umb-budget-enabled.log"
cp "$FLOPPY" "$BUDGET_IMAGE"
mcopy -o -i "$BUDGET_IMAGE" "$HIMEM" ::HIMEM.SYS
mcopy -o -i "$BUDGET_IMAGE" "$QEXIT" ::QEXIT.COM
{
    printf 'DEVICE=HIMEM.SYS\r\n'
    printf 'DEVICE=EMM386.EXE M5\r\n'
    printf 'DOS=HIGH,UMB\r\n'
} | mcopy -o -i "$BUDGET_IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nMEM\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BUDGET_IMAGE" - ::AUTOEXEC.BAT
run_image "$BUDGET_IMAGE" "$BUDGET_LOG"

cp "$FLOPPY" "$BUDGET_UMB_IMAGE"
mcopy -o -i "$BUDGET_UMB_IMAGE" "$HIMEM" ::HIMEM.SYS
mcopy -o -i "$BUDGET_UMB_IMAGE" "$QEXIT" ::QEXIT.COM
{
    printf 'DEVICE=HIMEM.SYS\r\n'
    printf 'DEVICE=EMM386.EXE RAM M5\r\n'
    printf 'DOS=HIGH,UMB\r\n'
} | mcopy -o -i "$BUDGET_UMB_IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nMEM\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$BUDGET_UMB_IMAGE" - ::AUTOEXEC.BAT
run_image "$BUDGET_UMB_IMAGE" "$BUDGET_UMB_LOG"

baseline_conventional=$(awk '$1 == "Conventional" { print $4; exit }' "$BUDGET_LOG" | tr -d '\r')
umb_conventional=$(awk '$1 == "Conventional" { print $4; exit }' "$BUDGET_UMB_LOG" | tr -d '\r')
baseline_under_1m=$(awk '$1 == "Total" && $2 == "under" { print $7; exit }' "$BUDGET_LOG" | tr -d '\r')
umb_under_1m=$(awk '$1 == "Total" && $2 == "under" { print $7; exit }' "$BUDGET_UMB_LOG" | tr -d '\r')
if [[ ! "$baseline_conventional" =~ ^[0-9]+$ \
    || ! "$umb_conventional" =~ ^[0-9]+$ \
    || ! "$baseline_under_1m" =~ ^[0-9]+$ \
    || ! "$umb_under_1m" =~ ^[0-9]+$ ]]
then
    echo 'FAIL: unable to parse UMB conventional-memory budget measurements' >&2
    exit 1
fi
if (( umb_conventional + 1024 < baseline_conventional )); then
    echo "FAIL: UMB mode consumed more than the 1024-byte conventional-memory budget" >&2
    echo "  baseline=$baseline_conventional UMB=$umb_conventional" >&2
    exit 1
fi
if (( umb_under_1m <= baseline_under_1m )); then
    echo 'FAIL: UMB mode did not increase usable memory below 1 MB' >&2
    echo "  baseline=$baseline_under_1m UMB=$umb_under_1m" >&2
    exit 1
fi

IMAGE="$OUT/mem-no-umb.img"
LOG="$OUT/mem-no-umb.log"
cp "$FLOPPY" "$IMAGE"
mcopy -o -i "$IMAGE" "$STATE" ::STATE.COM
mcopy -o -i "$IMAGE" "$QEXIT" ::QEXIT.COM
printf 'DOS=UMB\r\n' | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\nCTTY AUX\r\nMEM\r\nSTATE.COM\r\nQEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT
run_image "$IMAGE" "$LOG"

if ! grep -Eq '^  Upper +0 +0 +0' "$LOG" \
    || ! grep -Fq 'The high memory area is available.' "$LOG" \
    || ! grep -Fq 'LINK=0000' "$LOG"
then
    echo 'FAIL: MEM no-provider diagnostics or link restoration' >&2
    strings -a "$LOG" | sed -n '1,180p' >&2
    exit 1
fi

echo '  PASS: MEM UMB reporting, state restoration, and memory-manager footprint budgets'
