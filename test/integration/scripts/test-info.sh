#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare output
output=$(./fixture-tests info)

if ! echo "$output" | grep -q '"type": "external"'; then
    echo "FAIL: expected non-payload type 'external'" >&2
    exit 1
fi

if ! echo "$output" | grep -q '"product": "fixture"'; then
    echo "FAIL: expected product 'fixture'" >&2
    exit 1
fi

if ! echo "$output" | grep -q 'fixture/all'; then
    echo "FAIL: expected fixture/all suite" >&2
    exit 1
fi

if ! echo "$output" | grep -q 'fixture/smoke'; then
    echo "FAIL: expected fixture/smoke suite" >&2
    exit 1
fi

echo "PASS: info shows correct non-payload component"
exit 0
true
