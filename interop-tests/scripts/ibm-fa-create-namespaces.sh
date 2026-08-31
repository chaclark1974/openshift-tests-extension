#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare -a namespaces=("ibm-fusion-access" "ibm-spectrum-scale")

for ns in "${namespaces[@]}"; do
    if ! oc get namespace "${ns}" &>/dev/null; then
        oc create namespace "${ns}"
        echo "Created namespace ${ns}"
    else
        echo "Namespace ${ns} already exists"
    fi
done

# Verify both namespaces exist
declare -i failures=0
for ns in "${namespaces[@]}"; do
    if ! oc get namespace "${ns}" &>/dev/null; then
        echo "FAIL: namespace ${ns} does not exist after creation attempt" >&2
        failures+=1
    fi
done

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: ${failures} namespace(s) could not be verified" >&2
    exit 1
fi

echo "PASS: IBM Fusion Access namespaces created"
exit 0
true
