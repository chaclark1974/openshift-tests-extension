#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare crdName="virtualmachines.kubevirt.io"

if ! oc get crd "${crdName}" &>/dev/null; then
    echo "FAIL: CRD ${crdName} does not exist" >&2
    exit 1
fi

declare established
established=$(oc get crd "${crdName}" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || echo "NotFound")
if [[ "${established}" != "True" ]]; then
    echo "FAIL: CRD ${crdName} not established (status: ${established})" >&2
    exit 1
fi

echo "PASS: CRD ${crdName} exists and is established"
exit 0
true
