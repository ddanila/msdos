#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 STOPPED_ACCEPTANCE_IMAGE" >&2
    exit 2
fi

IMAGE=$1
command -v mtype >/dev/null 2>&1 || {
    echo "missing required tool: mtype" >&2
    exit 1
}
[[ -f "$IMAGE" ]] || {
    echo "missing acceptance image: $IMAGE" >&2
    exit 1
}

RESULT=$(mtype -i "$IMAGE" ::RESULT.TXT 2>/dev/null | tr -d '\r') || {
    echo "acceptance image has no readable RESULT.TXT" >&2
    exit 1
}

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
    'HMA_REQUEST AX=0000 BL=0391' \
    'HMA_REFERENCE_END' \
    'DOS_VERSION_AX=0005' \
    'CYCLE_ACCEPTANCE_DONE'
do
    if ! grep -Fq "$expected" <<<"$RESULT"; then
        echo "cycle-accurate acceptance missing: $expected" >&2
        printf '%s\n' "$RESULT" >&2
        exit 1
    fi
done

if ! grep -Eq '^ALLOC_0010 C=0 AX=[C-F][0-9A-F]{3} ' <<<"$RESULT" \
    || ! grep -Eq '^ALLOC_EXACT_LARGEST C=0 AX=[C-F][0-9A-F]{3} ' <<<"$RESULT"
then
    echo "cycle-accurate acceptance did not place both allocations in UMBs" >&2
    printf '%s\n' "$RESULT" >&2
    exit 1
fi
if grep -Eq '^(UMB|HMA)_FAILED$' <<<"$RESULT"; then
    echo "cycle-accurate acceptance probe reported failure" >&2
    printf '%s\n' "$RESULT" >&2
    exit 1
fi

echo "PASS: cycle-accurate 486 UMB/HMA acceptance"
