#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare output
output=$(./fixture-tests run-test "[sig-fixture] pass test" 2>&1) || true

if ! echo "$output" | grep -q '"passed"'; then
    echo "FAIL: expected 'passed' result" >&2
    echo "Output: ${output}" >&2
    exit 1
fi

echo "PASS: run-test pass works"
exit 0
true
