#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare output
output=$(./fixture-tests run-test "[sig-fixture] skip test" 2>&1) || true

if ! echo "$output" | grep -q '"skipped"'; then
    echo "FAIL: expected 'skipped' result" >&2
    echo "Output: ${output}" >&2
    exit 1
fi

echo "PASS: run-test skip works"
exit 0
true
