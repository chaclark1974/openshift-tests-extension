#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare namespace="open-cluster-management"

declare -a controllers=(
    "governance-policy-propagator"
)

declare -i failed=0
for controller in "${controllers[@]}"; do
    declare replicas
    replicas=$(oc get deployment -n "${namespace}" -l app="${controller}" -o jsonpath='{.items[0].status.availableReplicas}' 2>/dev/null || echo "0")
    if [[ "${replicas}" -eq 0 ]]; then
        echo "FAIL: ${controller} has no available replicas" >&2
        failed+=1
    else
        echo "OK: ${controller} has ${replicas} available replica(s)"
    fi
done

if [[ ${failed} -gt 0 ]]; then
    echo "FAIL: ${failed} governance controller(s) not available" >&2
    exit 1
fi

echo "PASS: governance policy controllers are running"
exit 0
true
