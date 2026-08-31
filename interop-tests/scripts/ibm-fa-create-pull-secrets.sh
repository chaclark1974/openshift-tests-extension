#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

if [[ -z "${IBM_ENTITLEMENT_KEY:-}" ]]; then
    echo "SKIP: IBM_ENTITLEMENT_KEY not set" >&2
    exit 2
fi

declare registry="cp.icr.io"
declare secretName="ibm-entitlement-key"
declare -a namespaces=("ibm-fusion-access" "ibm-spectrum-scale")

for ns in "${namespaces[@]}"; do
    if ! oc get namespace "${ns}" &>/dev/null; then
        echo "FAIL: namespace ${ns} does not exist -- create namespaces first" >&2
        exit 1
    fi

    if oc get secret "${secretName}" -n "${ns}" &>/dev/null; then
        oc delete secret "${secretName}" -n "${ns}"
        echo "Deleted existing secret ${secretName} in ${ns}"
    fi

    oc create secret docker-registry "${secretName}" \
        --docker-server="${registry}" \
        --docker-username=cp \
        --docker-password="${IBM_ENTITLEMENT_KEY}" \
        --docker-email=unused \
        -n "${ns}"
    echo "Created pull secret ${secretName} in ${ns}"
done

echo "PASS: Pull secrets created"
exit 0
true
