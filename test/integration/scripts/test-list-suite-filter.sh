#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare output
output=$(./fixture-tests list tests --suite fixture/smoke)

declare count
count=$(echo "$output" | grep -c '"name"')
if [[ "$count" -ne 3 ]]; then
    echo "FAIL: expected 3 SMOKE tests in fixture/smoke suite, got ${count}" >&2
    exit 1
fi

if echo "$output" | grep -q 'fail test'; then
    echo "FAIL: fail test should not be in smoke suite" >&2
    exit 1
fi

echo "PASS: suite filtering works correctly"
exit 0
true
