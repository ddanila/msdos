#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHOICE="$ROOT/src/CMD/CHOICE/CHOICE.COM"

run_choice() {
    local input=$1
    shift
    set +e
    CHOICE_OUTPUT=$(printf '%s' "$input" | "$ROOT/bin/dos-run" "$CHOICE" "$@" 2>&1)
    CHOICE_STATUS=$?
    set -e
}

run_choice $'n\r\n' /C:YN Continue
[[ $CHOICE_STATUS -eq 2 && "$CHOICE_OUTPUT" == *'Continue[Y,N]?'* ]]

run_choice $'A\r\n' /S /C:aA /N
[[ $CHOICE_STATUS -eq 2 && "$CHOICE_OUTPUT" == *A* ]]

run_choice '' /C:ABC /T:B,0 Timed
[[ $CHOICE_STATUS -eq 2 && "$CHOICE_OUTPUT" == *'Timed[A,B,C]?'* ]]

run_choice '' /C:AA
[[ $CHOICE_STATUS -eq 255 && "$CHOICE_OUTPUT" == *'Invalid choice switch.'* ]]

run_choice '' /C:YN /T:X,1
[[ $CHOICE_STATUS -eq 255 && "$CHOICE_OUTPUT" == *'Invalid choice switch.'* ]]

echo '  PASS: CHOICE prompt, redirected input, case sensitivity, timeout, and validation'
