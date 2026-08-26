#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/MS-DOS/v4.0/src"
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/msdos-native-tools.XXXXXX")
trap 'rm -f "$TEST_TMP"/*; rmdir "$TEST_TMP"' EXIT HUP INT TERM

"$ROOT/bin/dbof" \
    "$SRC/BOOT/MSBOOT.BIN $TEST_TMP/BOOT.INC 7c00 200"
cmp "$TEST_TMP/BOOT.INC" "$SRC/BOOT/BOOT.INC"

"$ROOT/bin/dbof" \
    "$SRC/CMD/FDISK/FDBOOT.BIN" "$TEST_TMP/FDBOOT.INC" 600 200
cmp "$TEST_TMP/FDBOOT.INC" "$SRC/CMD/FDISK/FDBOOT.INC"

cp "$SRC/MESSAGES/USA-MS.MSG" "$TEST_TMP/USA-MS.MSG"
python3 -c 'from pathlib import Path; import sys; p=Path(sys.argv[1]); d=p.read_bytes(); p.write_bytes(b"0087" + d[4:])' "$TEST_TMP/USA-MS.MSG"
"$ROOT/bin/buildidx" "$TEST_TMP/USA-MS.MSG"
cmp "$TEST_TMP/USA-MS.IDX" "$SRC/MESSAGES/USA-MS.IDX"
test "$(head -n 1 "$TEST_TMP/USA-MS.MSG" | tr -d '\r')" = 0088

echo "native DBOF and BUILDIDX parity tests passed"
