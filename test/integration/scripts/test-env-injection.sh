#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare output
output=$(./fixture-tests run-test "[sig-fixture] env echo test" 2>&1) || true

if ! echo "$output" | grep -q 'MY_TEST_VAR=from-manifest'; then
    echo "FAIL: expected manifest env var in output" >&2
    echo "Output: ${output}" >&2
    exit 1
fi

echo "PASS: manifest env vars injected into test"
exit 0
true
