#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare clusterCount
clusterCount=$(oc get managedclusters --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${clusterCount}" -eq 0 ]]; then
    echo "WARN: no managed clusters found — cluster lifecycle tests may not apply" >&2
    exit 2
fi

declare -i available=0
declare -i unavailable=0

while IFS= read -r line; do
    declare clusterName joinedStatus availableStatus
    clusterName=$(echo "${line}" | awk '{print $1}')
    joinedStatus=$(echo "${line}" | awk '{print $2}')
    availableStatus=$(echo "${line}" | awk '{print $3}')

    if [[ "${joinedStatus}" == "True" && "${availableStatus}" == "True" ]]; then
        available+=1
    else
        unavailable+=1
        echo "  Unavailable: ${clusterName} (joined=${joinedStatus}, available=${availableStatus})" >&2
    fi
done < <(oc get managedclusters --no-headers 2>/dev/null)

if [[ ${unavailable} -gt 0 ]]; then
    echo "FAIL: ${unavailable} managed clusters are not available" >&2
    exit 1
fi

echo "PASS: ${available} managed clusters joined and available"
exit 0
true
