#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare namespace="openshift-cnv"

declare availableReplicas
availableReplicas=$(oc get deployment virt-api -n "${namespace}" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
if [[ "${availableReplicas}" -eq 0 ]]; then
    echo "FAIL: virt-api deployment has no available replicas" >&2
    exit 1
fi

declare readyCondition
readyCondition=$(oc get deployment virt-api -n "${namespace}" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [[ "${readyCondition}" != "True" ]]; then
    echo "FAIL: virt-api deployment not available (status: ${readyCondition})" >&2
    exit 1
fi

echo "PASS: virt-api is available with ${availableReplicas} replicas"
exit 0
true
