#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

# Count worker nodes
declare -i workerCount=0
declare -i readyCount=0

while IFS= read -r line; do
    if [[ -z "${line}" ]]; then
        continue
    fi
    declare nodeName status
    nodeName=$(echo "${line}" | awk '{print $1}')
    status=$(echo "${line}" | awk '{print $2}')
    workerCount+=1
    if [[ "${status}" == "Ready" ]]; then
        readyCount+=1
        echo "OK: worker node ${nodeName} is Ready"
    else
        echo "WARNING: worker node ${nodeName} status is ${status}" >&2
    fi
done < <(oc get nodes -l node-role.kubernetes.io/worker --no-headers \
    -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type 2>/dev/null)

echo "Found ${workerCount} worker node(s), ${readyCount} Ready"

if [[ ${workerCount} -lt 3 ]]; then
    echo "FAIL: fewer than 3 worker nodes found (have ${workerCount}, need at least 3)" >&2
    exit 1
fi

if [[ ${readyCount} -lt ${workerCount} ]]; then
    echo "WARNING: not all worker nodes are Ready (${readyCount}/${workerCount})" >&2
fi

echo "PASS: ${workerCount} worker nodes available for Storage Scale"
exit 0
true
