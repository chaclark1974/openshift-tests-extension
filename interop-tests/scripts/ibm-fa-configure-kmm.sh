#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

if [[ -z "${KMM_REGISTRY_ORG:-}" ]]; then
    echo "SKIP: KMM_REGISTRY_ORG not set" >&2
    exit 2
fi

if [[ -z "${KMM_REGISTRY_REPO:-}" ]]; then
    echo "SKIP: KMM_REGISTRY_REPO not set" >&2
    exit 2
fi

declare -a namespaces=("ibm-fusion-access" "ibm-spectrum-scale-operator")

for ns in "${namespaces[@]}"; do
    # Ensure namespace exists; skip if not (operator may not have created it yet)
    if ! oc get namespace "${ns}" &>/dev/null; then
        echo "WARNING: namespace ${ns} does not exist -- skipping ConfigMap creation"
        continue
    fi

    cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: kmm-registry-config
  namespace: ${ns}
data:
  KMM_REGISTRY_ORG: "${KMM_REGISTRY_ORG}"
  KMM_REGISTRY_REPO: "${KMM_REGISTRY_REPO}"
EOF
    echo "Created/updated kmm-registry-config ConfigMap in ${ns}"
done

echo "PASS: KMM registry configured"
exit 0
true
