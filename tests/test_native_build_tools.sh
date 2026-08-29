#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/src"
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
cp "$TEST_TMP/USA-MS.MSG" "$TEST_TMP/USA-MS.ORIGINAL"
"$ROOT/bin/buildidx" "$TEST_TMP/USA-MS.MSG"
cmp "$TEST_TMP/USA-MS.MSG" "$TEST_TMP/USA-MS.ORIGINAL"
cmp "$TEST_TMP/USA-MS.IDX" "$SRC/MESSAGES/USA-MS.IDX"

echo "native DBOF and BUILDIDX parity tests passed"
python3 "$ROOT/tests/test_native_exe2bin.py"
python3 "$ROOT/tests/test_native_message_tools.py"
python3 "$ROOT/tests/test_native_convert.py"
python3 "$ROOT/tests/test_native_buildmsg.py"
python3 "$ROOT/tests/test_native_select_tools.py"
python3 "$ROOT/tests/test_native_mkcntry.py"
python3 "$ROOT/tests/test_toolchain_transforms.py"
python3 "$ROOT/tests/test_kernel_layout.py"

python3 - "$ROOT" "$TEST_TMP" <<'PY'
import runpy
import sys

root = sys.argv[1]
test_tmp = sys.argv[2]
wlib = runpy.run_path(root + "/bin/wlib")
resolved = wlib["resolve_existing_casefold"](
    root + "/src/MAPPER/mapper.lbr"
)
assert resolved.endswith("/MAPPER/MAPPER.LBR"), resolved

record = bytearray(b"prefix\x88\x08\x00\xc0\xfeT\x34\x12\x78\x56\0suffix")
record[16] = (-sum(record[6:16])) & 0xff
sample = test_tmp + "/wlib-timestamp-test.lib"
with open(sample, "wb") as stream:
    stream.write(record)
wlib["canonicalize_omf_timestamps"](sample)
normalized = open(sample, "rb").read()
assert normalized[12:16] == b"\0\0\0\0", normalized
assert sum(normalized[6:17]) & 0xff == 0, normalized
__import__("os").unlink(sample)
print("native WLIB case-folding and reproducibility tests passed")
PY

python3 - "$ROOT" <<'PY'
import os
import runpy
import tempfile
import sys

root = sys.argv[1]
wcc = runpy.run_path(root + "/bin/wcc")
with tempfile.TemporaryDirectory() as source, tempfile.TemporaryDirectory() as mirror:
    open(os.path.join(source, "HEADER.H"), "w").close()
    assert wcc["casefold_include_mirror"](source, mirror)
    assert os.path.exists(os.path.join(mirror, "header.h"))
print("native WCC case-insensitive include test passed")
PY
