#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare namespace="${VIRT_NAMESPACE:-openshift-cnv}"

if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "FAIL: namespace ${namespace} does not exist" >&2
    exit 1
fi

declare kvStatus
kvStatus=$(oc get kubevirt kubevirt-kubevirt-hyperconverged -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [[ "${kvStatus}" != "Deployed" ]]; then
    echo "FAIL: KubeVirt is not in Deployed phase (status: ${kvStatus})" >&2
    exit 1
fi

echo "PASS: KubeVirt is deployed in ${namespace} (phase: ${kvStatus})"
exit 0
true
