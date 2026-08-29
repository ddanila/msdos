#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
FLOPPY="$OUT/floppy.img"
HIMEM="$OUT/himem-core.sys"
REJECT_HIMEM="$OUT/HIMEM-REJECT.SYS"
BIOS_A20_HIMEM="$OUT/HIMEM-A20-BIOS.SYS"
KBC_A20_HIMEM="$OUT/HIMEM-A20-KBC.SYS"
XMS_PROBE="$OUT/xms-reference.com"
PROVIDER_PROBE="$OUT/himem-provider.com"
IMAGE="$OUT/floppy-himem.img"
LOG="$OUT/himem.log"
LIFECYCLE_PROBE="$OUT/umb-lifecycle-reference.com"
EXEC_PROBE="$OUT/umb-exec-reference.com"
EXEC_CHILD="$OUT/umbchild.com"
EMM_PROBE="$OUT/emm386-with-umb.com"
WARM_EMM_PROBE="$OUT/emm386-warm.com"
WARM_HMA_PROBE="$OUT/himem-warm-hma.com"
ISOLATION_PROBE="$OUT/umb-ems-isolation.com"
COMBINED_IMAGE="$OUT/floppy-himem-emm386.img"
COMBINED_LOG="$OUT/himem-emm386.log"
ABSENCE_PROBE="$OUT/umb-provider-absence.com"
ACTIVATION_PROBE_SRC="$ROOT/tests/emm386_activation_probe.asm"
ROLLBACK_IMAGE="$OUT/floppy-himem-emm386-rollback.img"
ROLLBACK_LOG="$OUT/himem-emm386-rollback.log"
FAULT_AFTER_MAP_EMM="$OUT/emm386-fault-after-map.sys"
FAULT_BEFORE_PUBLISH_EMM="$OUT/emm386-fault-before-publish.sys"
WARMBOOT="$OUT/warm-reboot.com"
QEXIT="$OUT/himem-qexit.com"
WARM_IMAGE="$OUT/floppy-himem-emm386-warm.img"
WARM_LOG="$OUT/himem-emm386-warm.log"
WARM_MONITOR="$OUT/himem-emm386-warm.monitor"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done

"$ROOT/bin/jwasm-bin" -Fo"$HIMEM" \
    "$ROOT/MS-DOS/v4.0/src/DEV/HIMEM/HIMEM.ASM"
"$ROOT/bin/jwasm-bin" -DUMB_TEST_REJECT -Fo"$REJECT_HIMEM" \
    "$ROOT/MS-DOS/v4.0/src/DEV/HIMEM/HIMEM.ASM"
"$ROOT/bin/jwasm-bin" -DA20_TEST_SKIP_FAST -Fo"$BIOS_A20_HIMEM" \
    "$ROOT/MS-DOS/v4.0/src/DEV/HIMEM/HIMEM.ASM"
"$ROOT/bin/jwasm-bin" -DA20_TEST_SKIP_FAST -DA20_TEST_SKIP_BIOS \
    -Fo"$KBC_A20_HIMEM" "$ROOT/MS-DOS/v4.0/src/DEV/HIMEM/HIMEM.ASM"
nasm -f bin "$ROOT/tests/xms_reference_probe.asm" -o "$XMS_PROBE"
nasm -f bin "$ROOT/tests/himem_provider_probe.asm" -o "$PROVIDER_PROBE"
nasm -f bin "$ROOT/tests/umb_lifecycle_reference.asm" -o "$LIFECYCLE_PROBE"
nasm -f bin "$ROOT/tests/umb_exec_reference.asm" -o "$EXEC_PROBE"
nasm -f bin "$ROOT/tests/umb_exit_child.asm" -o "$EXEC_CHILD"
nasm -f bin "$ROOT/tests/emm386_probe.asm" -o "$EMM_PROBE"
nasm -DNO_QEMU_EXIT -f bin "$ROOT/tests/emm386_probe.asm" -o "$WARM_EMM_PROBE"
nasm -f bin "$ROOT/tests/hma_reference_probe.asm" -o "$WARM_HMA_PROBE"
nasm -f bin "$ROOT/tests/umb_ems_isolation_probe.asm" -o "$ISOLATION_PROBE"
nasm -f bin "$ROOT/tests/umb_provider_absence_probe.asm" -o "$ABSENCE_PROBE"
nasm -f bin "$ROOT/tests/warm_reboot.asm" -o "$WARMBOOT"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"

build_fault_emm() {
    local define=$1
    local output=$2
    local work
    work=$(mktemp -d "${TMPDIR:-/tmp}/msdos-emm386-fault.XXXXXX")
    mkdir "$work/MEMM"
    cp -R "$ROOT/MS-DOS/v4.0/src/MEMM/MEMM" "$work/MEMM/MEMM"
    cp -R "$ROOT/MS-DOS/v4.0/src/MEMM/EMM" "$work/MEMM/EMM"
    find "$work" -type f \( -name '*.OBJ' -o -name '*.LIB' \
        -o -name 'EMM386.EXE' -o -name 'EMM386.SYS' \) -delete
    make -s -C "$ROOT" SRC="$work" \
        MEMM_AFLAGS="-Mx -t -DI386 -DNoBugMode -DNOHIMEM -D$define -I. -I..\\EMM" \
        memm >/dev/null
    cp "$work/MEMM/MEMM/EMM386.SYS" "$output"
    rm -rf "$work"
}

build_fault_emm UMB_TEST_FAIL_AFTER_MAP=1 "$FAULT_AFTER_MAP_EMM"
build_fault_emm UMB_TEST_FAIL_BEFORE_PUBLISH "$FAULT_BEFORE_PUBLISH_EMM"

cp "$FLOPPY" "$IMAGE"
mcopy -o -i "$IMAGE" "$HIMEM" ::HIMEM.SYS
mcopy -o -i "$IMAGE" "$XMS_PROBE" ::XMSREF.COM
mcopy -o -i "$IMAGE" "$PROVIDER_PROBE" ::HIMPROV.COM
{
    printf 'DEVICE=A:\\HIMEM.SYS\r\n'
    printf 'DOS=UMB\r\n'
} | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'XMSREF.COM\r\n'
    printf 'HIMPROV.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 25 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true

for expected in \
    'VERSION CF=0 AX=0200 BX=0100 DX=0001' \
    'MOVE_TO_XMS CF=0 AX=0001' \
    'MOVE_FROM_XMS CF=0 AX=0001' \
    'MOVE_VERIFY CF=0 AX=0001' \
    'LOCK CF=0 AX=0001 BX=0000 DX=0011' \
    'SHRUNK_INFO CF=0 AX=0001 BX=001F DX=0020' \
    'A20_FINAL CF=0 AX=0000' \
    'HIMEM_PROVIDER_PASS'
do
    if ! grep -Fq "$expected" "$LOG"; then
        echo "FAIL: repository HIMEM contract: $expected" >&2
        sed -n '1,180p' "$LOG" >&2
        exit 1
    fi
done

for expected_re in \
    '^BAD_HANDLE_FREE CF=0 AX=0000 BX=..A2 ' \
    '^ALLOCATE_ZERO CF=0 AX=0001 ' \
    '^LOCKED_FREE CF=0 AX=0000 BX=..AB ' \
    '^LOCKED_REALLOC CF=0 AX=0000 BX=..AB ' \
    '^UNLOCK_UNDERFLOW CF=0 AX=0000 BX=..AA ' \
    '^MOVE_ODD_LENGTH CF=0 AX=0000 BX=..A7 ' \
    '^MOVE_BAD_SOURCE CF=0 AX=0000 BX=..A3 ' \
    '^MOVE_BAD_DEST CF=0 AX=0000 BX=..A5 ' \
    '^MOVE_BAD_SOURCE_OFFSET CF=0 AX=0000 BX=..A7 ' \
    '^MOVE_OVERLAP CF=0 AX=0001 ' \
    '^MOVE_REVERSE_OVERLAP CF=0 AX=0001 ' \
    '^ALLOCATE_HUGE CF=0 AX=0000 BX=..A0 ' \
    '^HANDLE_EXHAUSTED CF=0 AX=0000 BX=..A1 DX=0020' \
    '^LOCK_OVERFLOW CF=0 AX=0000 BX=..AC ' \
    '^UNLOCK_AFTER_OVERFLOW CF=0 AX=0000 BX=..AA ' \
    '^HMA_SECOND_REQUEST CF=0 AX=0000 BX=..91 ' \
    '^HMA_SECOND_RELEASE CF=0 AX=0000 BX=..93 ' \
    '^A20_LOCAL_UNDERFLOW CF=0 AX=0000 BX=..82 '
do
    if ! grep -Eq "$expected_re" "$LOG"; then
        echo "FAIL: repository HIMEM error contract: $expected_re" >&2
        sed -n '1,220p' "$LOG" >&2
        exit 1
    fi
done

for backend in BIOS KBC; do
    backend_image="$OUT/floppy-himem-a20-${backend}.img"
    backend_log="$OUT/himem-a20-${backend}.log"
    if [[ "$backend" == BIOS ]]; then
        backend_driver=$BIOS_A20_HIMEM
    else
        backend_driver=$KBC_A20_HIMEM
    fi
    cp "$FLOPPY" "$backend_image"
    mcopy -o -i "$backend_image" "$backend_driver" ::HIMEM.SYS
    mcopy -o -i "$backend_image" "$XMS_PROBE" ::XMSREF.COM
    mcopy -o -i "$backend_image" "$PROVIDER_PROBE" ::HIMPROV.COM
    printf 'DEVICE=A:\\HIMEM.SYS\r\n' \
        | mcopy -o -i "$backend_image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'XMSREF.COM\r\n'
        printf 'HIMPROV.COM\r\n'
    } | mcopy -o -i "$backend_image" - ::AUTOEXEC.BAT
    timeout 25 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$backend_image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$backend_log" 2>&1 || true
    if ! grep -Fq 'A20_ON_QUERY CF=0 AX=0001' "$backend_log" \
        || ! grep -Fq 'A20_FINAL CF=0 AX=0000' "$backend_log"
    then
        echo "FAIL: HIMEM $backend A20 backend" >&2
        sed -n '1,180p' "$backend_log" >&2
        exit 1
    fi
done

cp "$FLOPPY" "$COMBINED_IMAGE"
mcopy -o -i "$COMBINED_IMAGE" "$HIMEM" ::HIMEM.SYS
mcopy -o -i "$COMBINED_IMAGE" "$LIFECYCLE_PROBE" ::UMBLREF.COM
mcopy -o -i "$COMBINED_IMAGE" "$EXEC_PROBE" ::UMBEXEC.COM
mcopy -o -i "$COMBINED_IMAGE" "$EXEC_CHILD" ::UMBCHILD.COM
mcopy -o -i "$COMBINED_IMAGE" "$EMM_PROBE" ::EMMPROBE.COM
mcopy -o -i "$COMBINED_IMAGE" "$ISOLATION_PROBE" ::UMBEMS.COM
{
    printf 'DEVICE=A:\\HIMEM.SYS\r\n'
    printf 'DEVICE=A:\\EMM386.SYS RAM M5\r\n'
    printf 'DOS=UMB\r\n'
} | mcopy -o -i "$COMBINED_IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'UMBLREF.COM\r\n'
    printf 'UMBEXEC.COM\r\n'
    printf 'UMBEMS.COM\r\n'
    printf 'EMMPROBE.COM\r\n'
} | mcopy -o -i "$COMBINED_IMAGE" - ::AUTOEXEC.BAT
timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$COMBINED_IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$COMBINED_LOG" 2>&1 || true

if ! grep -Fq 'UMB_LIFECYCLE_END' "$COMBINED_LOG" \
    || ! grep -Fq 'UMB_EXEC_PASS SEG=' "$COMBINED_LOG" \
    || ! grep -Eq '^ALLOC_0010 C=0 AX=[A-F][0-9A-F]{3}' "$COMBINED_LOG" \
    || ! grep -Eq '^ALLOC_AFTER_LARGEST (C=0 AX=[A-F][0-9A-F]{3}|C=1 AX=0008 BX=0000)' "$COMBINED_LOG" \
    || ! grep -Fq 'EMM386_API_PASS' "$COMBINED_LOG" \
    || ! grep -Fq 'UMB_EMS_ISOLATION_PASS' "$COMBINED_LOG"
then
    echo "FAIL: combined HIMEM/EMM386 UMB and EMS contract" >&2
    sed -n '1,220p' "$COMBINED_LOG" >&2
    exit 1
fi

cp "$FLOPPY" "$ROLLBACK_IMAGE"
mcopy -o -i "$ROLLBACK_IMAGE" "$REJECT_HIMEM" ::HIMEM.SYS
mcopy -o -i "$ROLLBACK_IMAGE" "$ABSENCE_PROBE" ::NOUMB.COM
mcopy -o -i "$ROLLBACK_IMAGE" "$EMM_PROBE" ::EMMPROBE.COM
{
    printf 'DEVICE=A:\\HIMEM.SYS\r\n'
    printf 'DEVICE=A:\\EMM386.SYS 16 RAM M5\r\n'
    printf 'DOS=UMB\r\n'
} | mcopy -o -i "$ROLLBACK_IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'NOUMB.COM\r\n'
    printf 'EMMPROBE.COM\r\n'
} | mcopy -o -i "$ROLLBACK_IMAGE" - ::AUTOEXEC.BAT
timeout 35 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$ROLLBACK_IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$ROLLBACK_LOG" 2>&1 || true

if ! grep -Fq 'UMB_PROVIDER_ABSENT_PASS' "$ROLLBACK_LOG" \
    || ! grep -Fq 'EMM386_API_PASS' "$ROLLBACK_LOG"
then
    echo 'FAIL: rejected UMB transaction did not roll back cleanly' >&2
    sed -n '1,220p' "$ROLLBACK_LOG" >&2
    exit 1
fi

for fault_spec in \
    "after-map|$FAULT_AFTER_MAP_EMM" \
    "before-publish|$FAULT_BEFORE_PUBLISH_EMM"
do
    IFS='|' read -r fault_name fault_driver <<<"$fault_spec"
    fault_image="$OUT/floppy-himem-emm386-fault-$fault_name.img"
    fault_log="$OUT/himem-emm386-fault-$fault_name.log"
    cp "$FLOPPY" "$fault_image"
    mcopy -o -i "$fault_image" "$HIMEM" ::HIMEM.SYS
    mcopy -o -i "$fault_image" "$fault_driver" ::EMM386.SYS
    mcopy -o -i "$fault_image" "$ABSENCE_PROBE" ::NOUMB.COM
    mcopy -o -i "$fault_image" "$EMM_PROBE" ::EMMPROBE.COM
    mcopy -o -i "$fault_image" "$QEXIT" ::QEXIT.COM
    {
        printf 'DEVICE=A:\\HIMEM.SYS\r\n'
        printf 'DEVICE=A:\\EMM386.SYS RAM M5\r\n'
        printf 'DOS=UMB\r\n'
    } | mcopy -o -i "$fault_image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\nCTTY AUX\r\n'
        printf 'NOUMB.COM\r\nEMMPROBE.COM\r\nQEXIT.COM\r\n'
    } | mcopy -o -i "$fault_image" - ::AUTOEXEC.BAT
    timeout 35 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$fault_image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$fault_log" 2>&1 || true
    if ! grep -Fq 'UMB_PROVIDER_ABSENT_PASS' "$fault_log" \
        || ! grep -Fq 'EMM386_API_PASS' "$fault_log"
    then
        echo "FAIL: UMB transaction fault did not roll back: $fault_name" >&2
        sed -n '1,220p' "$fault_log" >&2
        exit 1
    fi
done

for mode_spec in \
    'plain|0|1|M5|' \
    'ram|1|1|RAM M5|' \
    'noems|1|0|NOEMS|' \
    'exclude|1|1|RAM M5 X=E000-EFFF|-DEXPECT_ONE_REGION' \
    'include_precedence|1|0|NOEMS I=C000-CFFF X=C000-CFFF|-DEXPECT_ONE_REGION'
do
    IFS='|' read -r mode expect_umb expect_ems options extra_define \
        <<<"$mode_spec"
    mode_probe="$OUT/emm386-activation-$mode.com"
    mode_image="$OUT/floppy-emm386-activation-$mode.img"
    mode_log="$OUT/emm386-activation-$mode.log"
    nasm -DEXPECT_UMB="$expect_umb" -DEXPECT_EMS="$expect_ems" \
        ${extra_define:+"$extra_define"} -f bin "$ACTIVATION_PROBE_SRC" \
        -o "$mode_probe"
    cp "$FLOPPY" "$mode_image"
    mcopy -o -i "$mode_image" "$HIMEM" ::HIMEM.SYS
    mcopy -o -i "$mode_image" "$mode_probe" ::EMMMODE.COM
    mcopy -o -i "$mode_image" "$QEXIT" ::QEXIT.COM
    {
        printf 'DEVICE=A:\\HIMEM.SYS\r\n'
        printf 'DEVICE=A:\\EMM386.SYS %s\r\n' "$options"
        printf 'DOS=UMB\r\n'
    } | mcopy -o -i "$mode_image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'CTTY AUX\r\n'
        printf 'EMMMODE.COM\r\n'
        printf 'QEXIT.COM\r\n'
    } | mcopy -o -i "$mode_image" - ::AUTOEXEC.BAT
    timeout 25 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$mode_image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$mode_log" 2>&1 || true
    if ! grep -Fq 'EMM386_ACTIVATION_PASS' "$mode_log"; then
        echo "FAIL: EMM386 activation mode $mode" >&2
        sed -n '1,180p' "$mode_log" >&2
        exit 1
    fi
done

cp "$FLOPPY" "$WARM_IMAGE"
mcopy -o -i "$WARM_IMAGE" "$HIMEM" ::HIMEM.SYS
mcopy -o -i "$WARM_IMAGE" "$LIFECYCLE_PROBE" ::UMBLREF.COM
mcopy -o -i "$WARM_IMAGE" "$WARM_EMM_PROBE" ::EMMPROBE.COM
mcopy -o -i "$WARM_IMAGE" "$ISOLATION_PROBE" ::UMBEMS.COM
mcopy -o -i "$WARM_IMAGE" "$WARM_HMA_PROBE" ::HMAREF.COM
mcopy -o -i "$WARM_IMAGE" "$WARMBOOT" ::WARMBOOT.COM
mcopy -o -i "$WARM_IMAGE" "$QEXIT" ::QEXIT.COM
{
    printf 'DEVICE=A:\\HIMEM.SYS\r\n'
    printf 'DEVICE=A:\\EMM386.SYS RAM M5\r\n'
    printf 'DOS=HIGH,UMB\r\n'
} | mcopy -o -i "$WARM_IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'IF EXIST WARM.OK GOTO SECOND\r\n'
    printf 'ECHO WARM_FIRST_BOOT\r\n'
    printf 'HMAREF.COM\r\n'
    printf 'UMBLREF.COM\r\n'
    printf 'UMBEMS.COM\r\n'
    printf 'EMMPROBE.COM\r\n'
    printf 'ECHO READY>WARM.OK\r\n'
    printf 'WARMBOOT.COM\r\n'
    printf ':SECOND\r\n'
    printf 'ECHO WARM_SECOND_BOOT\r\n'
    printf 'HMAREF.COM\r\n'
    printf 'UMBLREF.COM\r\n'
    printf 'UMBEMS.COM\r\n'
    printf 'EMMPROBE.COM\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$WARM_IMAGE" - ::AUTOEXEC.BAT

rm -f "$WARM_LOG" "$WARM_MONITOR"
mkfifo "$WARM_MONITOR"
exec 9<>"$WARM_MONITOR"
qemu-system-i386 \
    -display none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$WARM_IMAGE",cache=writethrough \
    -boot a -serial file:"$WARM_LOG" \
    -monitor stdio \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 <&9 >/dev/null 2>&1 &
warm_pid=$!
cleanup_warm() {
    kill "$warm_pid" 2>/dev/null || true
    wait "$warm_pid" 2>/dev/null || true
    exec 9>&- 9<&-
    rm -f "$WARM_MONITOR"
}
trap cleanup_warm EXIT

for _ in $(seq 1 300); do
    grep -Fq 'WARM_RESET_READY' "$WARM_LOG" 2>/dev/null && break
    kill -0 "$warm_pid" 2>/dev/null || break
    sleep 0.1
done
if ! grep -Fq 'WARM_RESET_READY' "$WARM_LOG" 2>/dev/null; then
    echo 'FAIL: warm-reboot fixture did not reach its flushed reset point' >&2
    sed -n '1,260p' "$WARM_LOG" >&2
    exit 1
fi
printf 'system_reset\n' >&9

for _ in $(seq 1 400); do
    ! kill -0 "$warm_pid" 2>/dev/null && break
    sleep 0.1
done
cleanup_warm
trap - EXIT

if [[ $(grep -Fc 'UMB_LIFECYCLE_END' "$WARM_LOG") -ne 2 ]] \
    || [[ $(grep -Fc 'UMB_EMS_ISOLATION_PASS' "$WARM_LOG") -ne 2 ]] \
    || [[ $(grep -Fc 'EMM386_API_PASS' "$WARM_LOG") -ne 2 ]] \
    || [[ $(grep -Fc 'HMA_REFERENCE_END' "$WARM_LOG") -ne 2 ]] \
    || [[ $(grep -Ec '^HMA_REQUEST AX=0000 BL=..91' "$WARM_LOG") -ne 2 ]] \
    || ! grep -Fq 'WARM_FIRST_BOOT' "$WARM_LOG" \
    || ! grep -Fq 'WARM_SECOND_BOOT' "$WARM_LOG"
then
    echo 'FAIL: HIMEM/EMM386 state did not survive a complete warm-reboot cycle' >&2
    sed -n '1,300p' "$WARM_LOG" >&2
    exit 1
fi

echo "  PASS: repository XMS core, concurrent UMB/EMS, rollback, and warm reboot"
