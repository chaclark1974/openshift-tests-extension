#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare namespace="open-cluster-management"

if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "FAIL: namespace ${namespace} does not exist — ACM not installed" >&2
    exit 1
fi

declare mchStatus
mchStatus=$(oc get multiclusterhub multiclusterhub -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [[ "${mchStatus}" != "Running" ]]; then
    echo "FAIL: MultiClusterHub is not Running (status: ${mchStatus})" >&2
    exit 1
fi

echo "PASS: ACM MultiClusterHub is running in ${namespace}"
exit 0
true
