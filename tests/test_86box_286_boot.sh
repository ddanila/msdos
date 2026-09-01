#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C MTOOLS_SKIP_CHECK=1

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/tests/86box_286_lib.sh"

for tool in nasm python3; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2
        exit 1
    }
done
check_86box_286_prerequisites || exit $?

work=$(mktemp -d "${TMPDIR:-/tmp}/msdos-boot-286-86box.XXXXXX")
trap 'rm -rf "$work"' EXIT
image="$work/boot-286.img"

nasm -f bin "$ROOT/tests/86box_boot_probe.asm" -o "$work/boot.bin"
dd if=/dev/zero of="$image" bs=512 count=2400 status=none
dd if="$work/boot.bin" of="$image" bs=512 count=1 conv=notrunc status=none

run_86box_286 "$image" 86BOX_BOOT_PROBE_PASS 86BOX_BOOT_PROBE_FAIL \
    "${BOX86_TIMEOUT:-180}" "$ROOT" 0 >/dev/null
echo '  PASS: clean IBM AT 5170 BIOS boot on an 8 MHz 80286'
