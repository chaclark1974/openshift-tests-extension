#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

if ! oc get namespace open-cluster-management &>/dev/null; then
    echo "FAIL: open-cluster-management namespace does not exist — ACM hub not installed" >&2
    exit 1
fi

declare mchStatus
mchStatus=$(oc get multiclusterhub -A -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [[ "${mchStatus}" != "Running" ]]; then
    echo "FAIL: MultiClusterHub not in Running phase (status: ${mchStatus})" >&2
    exit 1
fi

echo "PASS: ACM hub is installed and MultiClusterHub is Running"
exit 0
true
