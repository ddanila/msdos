#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/out"
BASE="${FLOPPY_IMAGE:-$OUT/floppy.img}"
IMAGE="$OUT/floppy-setver.img"
LOG="$OUT/setver.log"
REBOOT_LOG="$OUT/setver-reboot.log"
CLEAR_LOG="$OUT/setver-clear.log"
PROBE="$OUT/SETPROBE.COM"
EXIT_COM="$OUT/qemu-exit.com"

for tool in nasm mcopy qemu-system-i386 timeout; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done

[[ -f "$BASE" ]] || {
    echo "ERROR: missing build artifact: $BASE" >&2
    exit 1
}

nasm -f bin "$ROOT/tests/setver_probe.asm" -o "$PROBE"
nasm -f bin "$ROOT/tests/qemu_exit.asm" -o "$EXIT_COM"
cp "$BASE" "$IMAGE"
mcopy -o -i "$IMAGE" "$PROBE" ::SETPROBE.COM
mcopy -o -i "$IMAGE" "$EXIT_COM" ::QEXIT.COM
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER SETPROBE.COM 3.30\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER\r\n'
    printf 'SETVER SETPROBE.COM 6.22\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER SETPROBE.COM /DELETE\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER A:\\ SETPROBE.COM 4.01\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER A:\\ SETPROBE.COM /delete\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER SETPROBE.COM 10.00\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER SETPROBE.COM 2.11\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER SETPROBE.COM /D /QUIET\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER A:\\ SETPROBE.COM 4.20\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER A:\\ SETPROBE.COM /DELETE /quiet\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER SETPROBE.COM 4.20\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT

timeout 30 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$LOG" 2>&1 || true

versions=$(grep -o 'SETVER_PROBE_VERSION=[0-9][0-9]*\.[0-9][0-9]' "$LOG" || true)
expected=$(printf '%s\n' \
    SETVER_PROBE_VERSION=6.22 \
    SETVER_PROBE_VERSION=3.30 \
    SETVER_PROBE_VERSION=6.22 \
    SETVER_PROBE_VERSION=6.22 \
    SETVER_PROBE_VERSION=4.01 \
    SETVER_PROBE_VERSION=6.22 \
    SETVER_PROBE_VERSION=6.22 \
    SETVER_PROBE_VERSION=2.11 \
    SETVER_PROBE_VERSION=6.22 \
    SETVER_PROBE_VERSION=4.20 \
    SETVER_PROBE_VERSION=6.22 \
    SETVER_PROBE_VERSION=4.20)
if [[ "$versions" != "$expected" ]]; then
    echo 'FAIL: SETVER version transitions differ' >&2
    printf 'Expected:\n%s\nActual:\n%s\n' "$expected" "$versions" >&2
    sed -n '1,200p' "$LOG" >&2
    exit 1
fi
grep -Fq 'SETPROBE.COM 3.30' "$LOG" || {
    echo 'FAIL: SETVER listing omitted the added entry' >&2
    sed -n '1,200p' "$LOG" >&2
    exit 1
}
while read -r expected_entry; do
    grep -Fq "$expected_entry" "$LOG" || {
        echo "FAIL: retail SETVER default missing: $expected_entry" >&2
        exit 1
    }
done <<'EOF'
KERNEL.EXE 5.00
NETX.COM 5.00
NETX.EXE 6.00
NET5.COM 5.00
BNETX.COM 5.00
BNETX.EXE 6.00
EMSNETX.EXE 6.00
EMSNET5.EXE 5.00
XMSNETX.EXE 6.00
XMSNET5.EXE 5.00
DOSOAD.SYS 5.00
EXTDISK.SYS 6.00
REDIR50.EXE 5.00
REDIR5.EXE 5.00
REDIRALL.EXE 5.00
REDIRNP4.EXE 5.00
EDLIN.EXE 5.00
BACKUP.EXE 5.00
ASSIGN.COM 5.00
EXE2BIN.EXE 5.00
JOIN.EXE 5.00
RECOVER.EXE 5.00
GRAFTABL.COM 5.00
LMSETUP.EXE 5.00
STACKER.COM 5.00
NCACHE.EXE 5.00
NCACHE2.EXE 5.00
IBMCACHE.SYS 5.00
XTRADRV.SYS 5.00
2XON.COM 5.00
WINWORD.EXE 4.10
EXCEL.EXE 4.10
LL3.EXE 4.01
REDIR4.EXE 4.00
REDIR40.EXE 4.00
MSREDIR.EXE 4.00
WIN200.BIN 3.40
METRO.EXE 3.31
VDISK.SYS 4.00
EOF
grep -Fq 'Entry added.' "$LOG"
grep -Fq 'Entry updated.' "$LOG"
grep -Fq 'Entry deleted.' "$LOG"
[[ "$(grep -Fc 'Entry deleted.' "$LOG")" -eq 2 ]] || {
    echo 'FAIL: /QUIET emitted a deletion confirmation' >&2
    sed -n '1,240p' "$LOG" >&2
    exit 1
}
grep -Fq 'Invalid version. Use major.minor.' "$LOG"

printf 'DEVICE=SETVER.EXE\r\n' | mcopy -o -i "$IMAGE" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'CTTY AUX\r\n'
    printf 'SETPROBE.COM\r\n'
    printf 'SETVER SETPROBE.COM /DELETE /QUIET\r\n'
    printf 'QEXIT.COM\r\n'
} | mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT
timeout 20 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$REBOOT_LOG" 2>&1 || true
grep -Fq 'SETVER_PROBE_VERSION=4.20' "$REBOOT_LOG" || {
    echo 'FAIL: CONFIG.SYS SETVER.EXE did not load the persisted table' >&2
    sed -n '1,160p' "$REBOOT_LOG" >&2
    exit 1
}

printf '@ECHO OFF\r\nCTTY AUX\r\nSETPROBE.COM\r\nQEXIT.COM\r\n' | \
    mcopy -o -i "$IMAGE" - ::AUTOEXEC.BAT
timeout 20 qemu-system-i386 \
    -display none -monitor none -machine pc -cpu 486 -m 8 \
    -drive if=floppy,index=0,format=raw,file="$IMAGE",cache=writethrough \
    -boot a -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$CLEAR_LOG" 2>&1 || true
grep -Fq 'SETVER_PROBE_VERSION=6.22' "$CLEAR_LOG" || {
    echo 'FAIL: persisted SETVER deletion did not survive reboot' >&2
    sed -n '1,160p' "$CLEAR_LOG" >&2
    exit 1
}

echo '  PASS: SETVER retail defaults, editing, persistence, CONFIG.SYS loading, and per-program versions'
