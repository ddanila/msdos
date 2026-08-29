#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FLOPPY="$ROOT/out/floppy.img"

for tool in dosbox-x nasm mcopy mtype; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done
[[ -f "$FLOPPY" ]] || {
    echo "ERROR: $FLOPPY not found — run 'make deploy' first" >&2
    exit 1
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/msdos-pre386.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
nasm -f bin "$ROOT/tests/pre386_fallback_probe.asm" -o "$WORK/pre386.com"

for cpu in 8086 286; do
    image="$WORK/pre386-$cpu.img"
    log="$WORK/pre386-$cpu.log"
    cp "$FLOPPY" "$image"
    mcopy -o -i "$image" "$WORK/pre386.com" ::PRE386.COM
    {
        printf 'DEVICE=A:\\HIMEM.SYS\r\n'
        printf 'DEVICE=A:\\EMM386.SYS NOEMS\r\n'
        printf 'DOS=HIGH,UMB\r\n'
    } | mcopy -o -i "$image" - ::CONFIG.SYS
    {
        printf '@ECHO OFF\r\n'
        printf 'PRE386.COM > A:\\RESULT.TXT\r\n'
    } | mcopy -o -i "$image" - ::AUTOEXEC.BAT

    SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
        dosbox-x -nogui -nomenu -fastlaunch -time-limit 20 \
        -set "cpu cputype=$cpu" \
        -c "boot $image" >"$log" 2>&1 || true
    result=$(mtype -i "$image" ::RESULT.TXT 2>/dev/null || true)
    if [[ "$result" != *PRE386_FALLBACK_PASS* ]] \
        || grep -Fq 'Illegal Unhandled Interrupt Called 6' "$log"; then
        echo "FAIL: pre-386 fallback on DOSBox-X cputype=$cpu" >&2
        printf '%s\n' "$result" >&2
        sed -n '1,160p' "$log" >&2
        exit 1
    fi
done

echo "  PASS: 8086/286 reject EMM386 safely and retain low-memory DOS services"
