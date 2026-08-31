#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare -a requiredCrds=(
    "policies.policy.open-cluster-management.io"
    "placementbindings.policy.open-cluster-management.io"
    "placementrules.apps.open-cluster-management.io"
)

declare -i missing=0
for crd in "${requiredCrds[@]}"; do
    if ! oc get crd "${crd}" &>/dev/null; then
        echo "FAIL: required CRD ${crd} not found" >&2
        missing+=1
    fi
done

if [[ ${missing} -gt 0 ]]; then
    echo "FAIL: ${missing} required policy CRD(s) missing" >&2
    exit 1
fi

echo "PASS: all required policy CRDs are present"
exit 0
true
