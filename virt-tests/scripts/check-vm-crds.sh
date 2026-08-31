#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare -a requiredCrds=(
    "virtualmachines.kubevirt.io"
    "virtualmachineinstances.kubevirt.io"
    "virtualmachineinstancemigrations.kubevirt.io"
    "virtualmachineinstancepresets.kubevirt.io"
    "virtualmachineinstancereplicasets.kubevirt.io"
)

declare -i missingCount=0
for crd in "${requiredCrds[@]}"; do
    declare condition
    condition=$(oc get crd "${crd}" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || echo "NotFound")
    if [[ "${condition}" != "True" ]]; then
        echo "FAIL: CRD ${crd} is not established (status: ${condition})" >&2
        missingCount+=1
    fi
done

if [[ ${missingCount} -gt 0 ]]; then
    echo "FAIL: ${missingCount} required KubeVirt CRDs are missing or not established" >&2
    exit 1
fi

echo "PASS: all ${#requiredCrds[@]} KubeVirt CRDs are established"
exit 0
true
