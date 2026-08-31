#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare -i degradedOps=0
while IFS= read -r line; do
    declare coName coAvailable coDegraded
    coName=$(echo "${line}" | awk '{print $1}')
    coAvailable=$(echo "${line}" | awk '{print $3}')
    coDegraded=$(echo "${line}" | awk '{print $5}')

    if [[ "${coDegraded}" == "True" ]]; then
        degradedOps+=1
        echo "  Degraded: ${coName}" >&2
    fi
    if [[ "${coAvailable}" != "True" ]]; then
        degradedOps+=1
        echo "  Not Available: ${coName}" >&2
    fi
done < <(oc get clusteroperators --no-headers 2>/dev/null)

if [[ ${degradedOps} -gt 0 ]]; then
    echo "FAIL: ${degradedOps} cluster operator issues detected" >&2
    exit 1
fi

declare -i notReadyNodes=0
while IFS= read -r line; do
    declare nodeName nodeStatus
    nodeName=$(echo "${line}" | awk '{print $1}')
    nodeStatus=$(echo "${line}" | awk '{print $2}')
    if [[ "${nodeStatus}" != "Ready" ]]; then
        notReadyNodes+=1
        echo "  Not Ready: ${nodeName} (${nodeStatus})" >&2
    fi
done < <(oc get nodes --no-headers 2>/dev/null)

if [[ ${notReadyNodes} -gt 0 ]]; then
    echo "FAIL: ${notReadyNodes} nodes are not Ready" >&2
    exit 1
fi

declare nodeCount
nodeCount=$(oc get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
declare coCount
coCount=$(oc get clusteroperators --no-headers 2>/dev/null | wc -l | tr -d ' ')

echo "PASS: cluster healthy — ${coCount} operators available, ${nodeCount} nodes ready"
exit 0
true
