#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare namespace="openshift-compliance"

if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "FAIL: namespace ${namespace} does not exist — Compliance Operator not installed" >&2
    exit 1
fi

declare readyReplicas
readyReplicas=$(oc get deployment compliance-operator -n "${namespace}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "${readyReplicas}" -eq 0 ]]; then
    echo "FAIL: compliance-operator deployment has no ready replicas" >&2
    exit 1
fi

declare profileCount
profileCount=$(oc get complianceprofiles -n "${namespace}" --no-headers 2>/dev/null | wc -l | tr -d ' ')

echo "PASS: Compliance Operator running with ${readyReplicas} replicas, ${profileCount} profiles available"
exit 0
true
