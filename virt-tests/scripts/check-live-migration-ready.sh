#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare namespace="${VIRT_NAMESPACE:-openshift-cnv}"

declare liveMigrateCondition
liveMigrateCondition=$(oc get kubevirt kubevirt-kubevirt-hyperconverged -n "${namespace}" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "False")
if [[ "${liveMigrateCondition}" != "True" ]]; then
    echo "FAIL: KubeVirt not available — live migration cannot be evaluated" >&2
    exit 1
fi

declare nodeCount
nodeCount=$(oc get nodes --selector='node-role.kubernetes.io/worker' --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${nodeCount}" -lt 2 ]]; then
    echo "WARN: only ${nodeCount} worker node(s) — live migration requires at least 2" >&2
    exit 2
fi

echo "PASS: live migration prerequisites met (${nodeCount} worker nodes, KubeVirt available)"
exit 0
true
