#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare namespace="${VIRT_NAMESPACE:-openshift-cnv}"

declare readyReplicas
readyReplicas=$(oc get deployment virt-controller -n "${namespace}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "${readyReplicas}" -eq 0 ]]; then
    echo "FAIL: virt-controller has no ready replicas" >&2
    exit 1
fi

declare availableCondition
availableCondition=$(oc get deployment virt-controller -n "${namespace}" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "False")
if [[ "${availableCondition}" != "True" ]]; then
    echo "FAIL: virt-controller is not Available" >&2
    exit 1
fi

echo "PASS: virt-controller is available with ${readyReplicas} ready replicas"
exit 0
true
