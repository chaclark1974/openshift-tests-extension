#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare output
output=$(./fixture-tests run-test "[sig-fixture] fail test" 2>&1) || true

if ! echo "$output" | grep -q '"failed"'; then
    echo "FAIL: expected 'failed' result" >&2
    echo "Output: ${output}" >&2
    exit 1
fi

echo "PASS: run-test fail works"
exit 0
true
