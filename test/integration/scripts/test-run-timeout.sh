#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare startTime
startTime=$(date +%s)

declare output
output=$(./fixture-tests run-test "[sig-fixture] timeout test" 2>&1) || true

declare endTime
endTime=$(date +%s)
declare elapsed=$(( endTime - startTime ))

if ! echo "$output" | grep -q '"failed"'; then
    echo "FAIL: expected 'failed' result for timed-out test" >&2
    exit 1
fi

if ! echo "$output" | grep -q 'timed out'; then
    echo "FAIL: expected 'timed out' in error message" >&2
    exit 1
fi

if [[ "$elapsed" -gt 30 ]]; then
    echo "FAIL: timeout took ${elapsed}s, expected under 30s (configured 3s + signal escalation)" >&2
    exit 1
fi

echo "PASS: timeout test killed within expected window (${elapsed}s)"
exit 0
true
