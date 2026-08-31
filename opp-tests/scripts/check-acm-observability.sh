#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare namespace="open-cluster-management-observability"

if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "WARN: observability namespace ${namespace} does not exist — observability may not be configured" >&2
    exit 2
fi

declare obsStatus
obsStatus=$(oc get multiclusterobservability observability -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")

if [[ "${obsStatus}" != "True" ]]; then
    echo "FAIL: MultiClusterObservability is not Ready (status: ${obsStatus})" >&2
    exit 1
fi

echo "PASS: ACM Observability is ready"
exit 0
true
