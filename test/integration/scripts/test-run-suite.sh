#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare output
output=$(./fixture-tests run-suite fixture/smoke 2>&1) || true

if ! echo "$output" | grep -q '"passed"'; then
    echo "FAIL: expected at least one 'passed' result in suite" >&2
    exit 1
fi

declare passCount
passCount=$(echo "$output" | grep -c '"passed"' || true)
if [[ "$passCount" -lt 2 ]]; then
    echo "FAIL: expected at least 2 passed tests in smoke suite, got ${passCount}" >&2
    exit 1
fi

echo "PASS: run-suite produces correct results"
exit 0
true
