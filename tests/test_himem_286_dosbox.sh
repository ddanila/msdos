#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FLOPPY=${FLOPPY_IMAGE:-$ROOT/out/floppy.img}

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

work=$(mktemp -d "${TMPDIR:-/tmp}/msdos-himem-286.XXXXXX")
trap 'rm -rf "$work"' EXIT
image="$work/himem-286.img"
log="$work/himem-286.log"
cp "$FLOPPY" "$image"
nasm -f bin "$ROOT/tests/himem_286_probe.asm" -o "$work/HIM286.COM"
mcopy -o -i "$image" "$work/HIM286.COM" ::HIM286.COM
printf 'DEVICE=A:\\HIMEM.SYS\r\n' | mcopy -o -i "$image" - ::CONFIG.SYS
{
    printf '@ECHO OFF\r\n'
    printf 'HIM286.COM > A:\\RESULT.TXT\r\n'
} | mcopy -o -i "$image" - ::AUTOEXEC.BAT

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    dosbox-x -nogui -nomenu -fastlaunch -time-limit 25 \
    -set 'cpu cputype=286' -c "boot $image" >"$log" 2>&1 || true
result=$(mtype -i "$image" ::RESULT.TXT 2>/dev/null || true)
if [[ "$result" != *HIMEM_286_PASS* ]] \
    || grep -Fq 'Illegal Unhandled Interrupt Called 6' "$log"; then
    echo 'FAIL: HIMEM XMS lifecycle on a 286' >&2
    printf '%s\n' "$result" >&2
    sed -n '1,160p' "$log" >&2
    exit 1
fi

echo '  PASS: HIMEM installs and serves the XMS lifecycle on a 286'
