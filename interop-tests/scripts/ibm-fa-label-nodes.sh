#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

# Remove existing scale label from worker nodes (ignore errors if label does not exist)
oc label nodes --selector='node-role.kubernetes.io/worker' scale- 2>/dev/null || true
echo "Cleared existing scale labels from worker nodes"

# Apply scale=true label to all worker nodes
oc label nodes --selector='node-role.kubernetes.io/worker' scale=true --overwrite
echo "Applied scale=true label to worker nodes"

# Verify labels were applied
declare -i labeledCount=0
while IFS= read -r nodeName; do
    if [[ -n "${nodeName}" ]]; then
        declare labelVal
        labelVal=$(oc get node "${nodeName}" -o jsonpath='{.metadata.labels.scale}' 2>/dev/null) || true
        if [[ "${labelVal}" == "true" ]]; then
            labeledCount+=1
        else
            echo "WARNING: node ${nodeName} does not have scale=true label" >&2
        fi
    fi
done < <(oc get nodes -l node-role.kubernetes.io/worker --no-headers \
    -o custom-columns=NAME:.metadata.name 2>/dev/null)

if [[ ${labeledCount} -eq 0 ]]; then
    echo "FAIL: no worker nodes were labeled with scale=true" >&2
    exit 1
fi

echo "PASS: Worker nodes labeled for Storage Scale (${labeledCount} nodes)"
exit 0
true
