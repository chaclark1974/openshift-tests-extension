#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare namespace="${VIRT_NAMESPACE:-openshift-cnv}"

declare desiredCount
desiredCount=$(oc get daemonset virt-handler -n "${namespace}" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
if [[ "${desiredCount}" -eq 0 ]]; then
    echo "FAIL: virt-handler daemonset not found or has 0 desired pods" >&2
    exit 1
fi

declare readyCount
readyCount=$(oc get daemonset virt-handler -n "${namespace}" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
if [[ "${readyCount}" -lt "${desiredCount}" ]]; then
    echo "FAIL: virt-handler has ${readyCount}/${desiredCount} ready pods" >&2
    exit 1
fi

echo "PASS: virt-handler daemonset is healthy (${readyCount}/${desiredCount} ready)"
exit 0
true
