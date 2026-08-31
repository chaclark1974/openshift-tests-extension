#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare quayUrl="${QUAY_URL:-https://quay.io}"

declare response
response=$(curl -sk -o /dev/null -w "%{http_code}" "${quayUrl}/api/v1/discovery")

if [[ "$response" == "200" ]]; then
    echo "Quay API is healthy (HTTP ${response})"
    exit 0
else
    echo "Quay API health check failed (HTTP ${response})"
    exit 1
fi
true
