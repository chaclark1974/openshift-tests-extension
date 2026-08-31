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

declare isPublic
isPublic=$(echo "$response" | grep -o '"is_public": *[a-z]*' | head -1 | awk '{print $2}')

if [[ "$isPublic" == "true" ]]; then
    echo "Repository ${repo} is public as expected"
    exit 0
else
    echo "Repository ${repo} is not public (is_public=${isPublic})"
    exit 1
fi
true
