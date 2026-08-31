#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare output
output=$(./fixture-tests list tests)

declare count
count=$(echo "$output" | grep -c '"name"')
if [[ "$count" -ne 6 ]]; then
    echo "FAIL: expected 6 tests, got ${count}" >&2
    exit 1
fi

if ! echo "$output" | grep -q '"product": "fixture"'; then
    echo "FAIL: missing product tag" >&2
    exit 1
fi

if ! echo "$output" | grep -q '"lifecycle": "blocking"'; then
    echo "FAIL: missing lifecycle field" >&2
    exit 1
fi

if ! echo "$output" | grep -q '"source": "fixture:external:fixture-tests"'; then
    echo "FAIL: missing or incorrect source (expected non-payload external)" >&2
    exit 1
fi

echo "PASS: list tests returns correct output"
exit 0
true
