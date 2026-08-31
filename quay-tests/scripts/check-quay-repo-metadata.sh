#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare quayUrl="${QUAY_URL:-https://quay.io}"
declare repo="${QUAY_TEST_REPO:-quay/test}"

declare response
response=$(curl -sk "${quayUrl}/api/v1/repository/${repo}")
declare httpCode
httpCode=$(curl -sk -o /dev/null -w "%{http_code}" "${quayUrl}/api/v1/repository/${repo}")

if [[ "$httpCode" != "200" ]]; then
    echo "Failed to reach Quay repository API (HTTP ${httpCode})"
    exit 1
fi

declare namespace
namespace=$(echo "$response" | grep -o '"namespace": *"[^"]*"' | head -1 | cut -d'"' -f4)
declare name
name=$(echo "$response" | grep -o '"name": *"[^"]*"' | head -1 | cut -d'"' -f4)
declare kind
kind=$(echo "$response" | grep -o '"kind": *"[^"]*"' | head -1 | cut -d'"' -f4)
declare state
state=$(echo "$response" | grep -o '"state": *"[^"]*"' | head -1 | cut -d'"' -f4)

declare -i failed=0

if [[ "$namespace" != "quay" ]]; then
    echo "FAIL: namespace expected 'quay', got '${namespace}'"
    failed=1
fi

if [[ "$name" != "test" ]]; then
    echo "FAIL: name expected 'test', got '${name}'"
    failed=1
fi

if [[ "$kind" != "image" ]]; then
    echo "FAIL: kind expected 'image', got '${kind}'"
    failed=1
fi

if [[ "$state" != "NORMAL" ]]; then
    echo "FAIL: state expected 'NORMAL', got '${state}'"
    failed=1
fi

if [[ "$failed" -eq 0 ]]; then
    echo "All metadata checks passed (namespace=${namespace}, name=${name}, kind=${kind}, state=${state})"
    exit 0
else
    exit 1
fi
true
