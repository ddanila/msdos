#!/bin/bash

set -euo pipefail
export LC_ALL=C MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
FLOPPY="$OUT/floppy.img"
IMAGE="$OUT/floppy-himem-options.img"
LOG="$OUT/himem-options.log"
PROBE="$OUT/himem-options.com"
REJECT_PROBE="$OUT/himem-reject.com"
ACCEPT_PROBE="$OUT/himem-accept.com"
FAULT_HIMEM="$OUT/himem-testmem-fault.sys"
VERBOSE_IMAGE="$OUT/floppy-himem-verbose.img"
VERBOSE_QMP="$OUT/himem-verbose-qmp.sock"
VERBOSE_SCREEN="$OUT/himem-verbose-screen.log"
QEXIT="$OUT/himem-options-qexit.com"
EISA_PROBE="$OUT/himem-eisa.com"

for tool in nasm mcopy python3 qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null || { echo "ERROR: missing $tool"; exit 1; }
done

nasm -f bin "$ROOT/tests/himem_options_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/himem_reject_probe.asm" -o "$REJECT_PROBE"
nasm -f bin -DEXPECT_INSTALLED=1 "$ROOT/tests/himem_reject_probe.asm" -o "$ACCEPT_PROBE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$QEXIT"
"$ROOT/bin/jwasm-bin" -DTESTMEM_FAULT -Fo"$FAULT_HIMEM" \
    "$ROOT/src/DEV/HIMEM/HIMEM.ASM"
cp "$FLOPPY" "$IMAGE"
mdel -i "$IMAGE" ::HELP.HLP >/dev/null 2>&1 || true
mcopy -o -i "$IMAGE" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
mcopy -o -i "$IMAGE" "$PROBE" ::HIMOPT.COM
{
    printf 'DEVICE=A:\\HIMEM.SYS /HMAMIN=1 /NUMHANDLES=3 /INT15=128 /MACHINE:PS2 /A20CONTROL:ON /SHADOWRAM:OFF /CPUCLOCK:OFF /EISA /TESTMEM:OFF /VERBOSE\r\n'
} | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'HIMOPT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 25 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true

grep -Fq 'HIMEM_OPTIONS_PASS' "$LOG" || {
    sed -n '1,160p' "$LOG" >&2
    exit 1
}

for testmem_mode in ON OFF; do
    testmem_image="$OUT/floppy-himem-testmem-$testmem_mode.img"
    testmem_log="$OUT/himem-testmem-$testmem_mode.log"
    cp "$FLOPPY" "$testmem_image"
    mdel -i "$testmem_image" ::HELP.HLP >/dev/null 2>&1 || true
    mcopy -o -i "$testmem_image" "$FAULT_HIMEM" ::HIMEM.SYS
    if [[ "$testmem_mode" == ON ]]; then
        testmem_probe="$REJECT_PROBE"
    else
        testmem_probe="$ACCEPT_PROBE"
    fi
    mcopy -o -i "$testmem_image" "$testmem_probe" ::HIMTEST.COM
    printf 'DEVICE=A:\\HIMEM.SYS /TESTMEM:%s\r\n' "$testmem_mode" | \
        mcopy -o -i "$testmem_image" - ::CONFIG.SYS
    printf '@ECHO OFF\r\nCTTY AUX\r\nHIMTEST.COM\r\n' | \
        mcopy -o -i "$testmem_image" - ::AUTOEXEC.BAT
    timeout 20 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$testmem_image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$testmem_log" 2>&1 || true
    grep -Fq HIMEM_REJECT_PASS "$testmem_log"
done

cp "$FLOPPY" "$VERBOSE_IMAGE"
mcopy -o -i "$VERBOSE_IMAGE" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
mcopy -o -i "$VERBOSE_IMAGE" "$QEXIT" ::QEXIT.COM
printf 'DEVICE=A:\\HIMEM.SYS /V\r\n' | \
    mcopy -o -i "$VERBOSE_IMAGE" - ::CONFIG.SYS
printf '@ECHO OFF\r\nPAUSE\r\nCHOICE /N /T:Y,2 >NUL\r\nQEXIT.COM\r\n' | \
    mcopy -o -i "$VERBOSE_IMAGE" - ::AUTOEXEC.BAT
rm -f "$VERBOSE_QMP" "$VERBOSE_SCREEN"
timeout 20 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 16 \
    -drive if=floppy,index=0,format=raw,file="$VERBOSE_IMAGE",cache=writethrough \
    -boot a -qmp unix:"$VERBOSE_QMP",server,nowait -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
verbose_pid=$!
python3 "$ROOT/tests/screen_expect.py" "$VERBOSE_QMP" "$VERBOSE_SCREEN" \
    'HIMEM: DOS 6 extended-memory manager installed' 'ret'
wait "$verbose_pid" || true
grep -Fq 'HIMEM: DOS 6 extended-memory manager installed' "$VERBOSE_SCREEN"

for eisa_mode in EISA LEGACY; do
    eisa_image="$OUT/floppy-himem-eisa-$eisa_mode.img"
    eisa_log="$OUT/himem-eisa-$eisa_mode.log"
    cp "$FLOPPY" "$eisa_image"
    if [[ "$eisa_mode" == EISA ]]; then
        nasm -f bin -DEXPECT_EISA=1 "$ROOT/tests/himem_eisa_probe.asm" -o "$EISA_PROBE"
        option='/EISA /TESTMEM:OFF'
    else
        nasm -f bin "$ROOT/tests/himem_eisa_probe.asm" -o "$EISA_PROBE"
        option=/TESTMEM:OFF
    fi
    mcopy -o -i "$eisa_image" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
    mcopy -o -i "$eisa_image" "$EISA_PROBE" ::EISAPRB.COM
    printf 'DEVICE=A:\\HIMEM.SYS %s\r\n' "$option" | \
        mcopy -o -i "$eisa_image" - ::CONFIG.SYS
    printf '@ECHO OFF\r\nCTTY AUX\r\nEISAPRB.COM\r\n' | \
        mcopy -o -i "$eisa_image" - ::AUTOEXEC.BAT
    timeout 20 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 128 \
        -drive if=floppy,index=0,format=raw,file="$eisa_image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$eisa_log" 2>&1 || true
    grep -Fq HIMEM_EISA_PASS "$eisa_log"
done

for option in \
    '/HMAMIN=64' '/NUMHANDLES=0' '/NUMHANDLES=129' '/INT15=65536' \
    '/MACHINE:UNKNOWN' '/A20CONTROL:MAYBE' '/SHADOWRAM:MAYBE' '/CPUCLOCK:MAYBE' \
    '/EISA:ON' '/VERBOSE:ON' '/TESTMEM:MAYBE'
do
    tag=$(printf '%s' "$option" | tr -c 'A-Za-z0-9' '_')
    reject_image="$OUT/floppy-himem-reject-$tag.img"
    reject_log="$OUT/himem-reject-$tag.log"
    cp "$FLOPPY" "$reject_image"
    mdel -i "$reject_image" ::HELP.HLP >/dev/null 2>&1 || true
    mcopy -o -i "$reject_image" "$ROOT/src/DEV/HIMEM/HIMEM.SYS" ::HIMEM.SYS
    mcopy -o -i "$reject_image" "$REJECT_PROBE" ::HIMREJ.COM
    printf 'DEVICE=A:\\HIMEM.SYS %s\r\n' "$option" \
        | mcopy -o -i "$reject_image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\nCTTY AUX\r\nHIMREJ.COM\r\n'
    } | mcopy -o -i "$reject_image" - ::AUTOEXEC.BAT
    timeout 20 qemu-system-i386 \
        -display none -monitor none -machine pc -cpu 486 -m 16 \
        -drive if=floppy,index=0,format=raw,file="$reject_image",cache=writethrough \
        -boot a -serial stdio -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$reject_log" 2>&1 || true
    grep -Fq HIMEM_REJECT_PASS "$reject_log" || {
        echo "HIMEM accepted invalid option: $option" >&2
        sed -n '1,100p' "$reject_log" >&2
        exit 1
    }
done

echo 'HIMEM documented option semantics and rejection boundaries passed'
