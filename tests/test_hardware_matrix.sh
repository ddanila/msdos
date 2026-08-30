#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FLOPPY=${FLOPPY_IMAGE:-$ROOT/out/floppy.img}

for tool in dosbox-x mcopy mtype nasm; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done
[[ -f "$FLOPPY" ]] || {
    echo "ERROR: $FLOPPY not found; run 'make deploy' first" >&2
    exit 1
}

bash "$ROOT/tests/test_himem_286_dosbox.sh"

work=$(mktemp -d "${TMPDIR:-/tmp}/msdos-hardware-matrix.XXXXXX")
trap 'rm -rf "$work"' EXIT
for cpu in 386 486; do
    image="$work/hardware-$cpu.img"
    log="$work/hardware-$cpu.log"
    bash "$ROOT/tests/prepare_86box_umb_acceptance.sh" "$FLOPPY" "$image" \
        >/dev/null
    SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
        dosbox-x -nogui -nomenu -fastlaunch -time-limit 30 \
        -set "cpu cputype=$cpu" -set 'cpu cycles=fixed 6000' \
        -c "boot $image" >"$log" 2>&1 || true
    result=$(mtype -i "$image" ::RESULT.TXT 2>/dev/null | tr -d '\r' || true)
    for expected in \
        'LINK C=0' \
        'LIVE_VALUE=5AA5' \
        'UNLINK_LIVE C=0' \
        'RELINK_LIVE C=0' \
        'FREE_LIVE C=0' \
        'UPPER_NO_FALLBACK C=1 AX=0008' \
        'UPPER_THEN_LOW C=0' \
        'INT2F_CHAIN_RETURNED' \
        'A20 AX=0001' \
        'HMA_REFERENCE_END' \
        'DOS_VERSION_AX=1606' \
        'CYCLE_ACCEPTANCE_DONE'
    do
        grep -Fq "$expected" <<<"$result" || {
            echo "FAIL: $cpu model missing: $expected" >&2
            printf '%s\n' "$result" >&2
            exit 1
        }
    done
    grep -Eq '^HMA_REQUEST AX=0000 BL=[0-9A-F]{4}$' <<<"$result" || {
        echo "FAIL: $cpu model did not grant the HMA" >&2
        printf '%s\n' "$result" >&2
        exit 1
    }
    grep -Eq '^ALLOC_0010 C=0 AX=[C-F][0-9A-F]{3} ' <<<"$result" || {
        echo "FAIL: $cpu model did not allocate a UMB" >&2
        printf '%s\n' "$result" >&2
        exit 1
    }
    if grep -Eq '^(UMB|HMA)_FAILED$' <<<"$result" ||
       grep -Eq 'Illegal Unhandled Interrupt Called 6([^0-9]|$)' "$log"; then
        echo "FAIL: $cpu model reported a CPU or memory-manager failure" >&2
        printf '%s\n' "$result" >&2
        exit 1
    fi
    echo "  PASS: DOS/HIMEM/EMM386 HMA and UMB lifecycle on a $cpu model"
done
