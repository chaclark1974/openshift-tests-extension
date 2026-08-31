#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare namespace="ibm-fusion-access"

# Check namespace exists
if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "FAIL: namespace ${namespace} does not exist -- create namespaces first" >&2
    exit 1
fi

# Apply FusionAccess CR
cat <<EOF | oc apply -f -
apiVersion: fusion.ibm.com/v1
kind: FusionAccess
metadata:
  name: fusionaccess
  namespace: ${namespace}
spec:
  license:
    accept: true
EOF
echo "Applied FusionAccess CR in ${namespace}"

# Wait for the resource to be created and available
declare -i timeout=300
declare -i elapsed=0
echo "Waiting for FusionAccess resource to be created (timeout ${timeout}s)..."
while [[ ${elapsed} -lt ${timeout} ]]; do
    if oc get fusionaccess fusionaccess -n "${namespace}" &>/dev/null; then
        echo "FusionAccess resource exists"
        break
    fi
    sleep 10
    elapsed+=10
done

if ! oc get fusionaccess fusionaccess -n "${namespace}" &>/dev/null; then
    echo "FAIL: FusionAccess resource was not created within ${timeout}s" >&2
    exit 1
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get fusionaccess fusionaccess -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/fusionaccess.yaml" 2>/dev/null || true
fi

echo "PASS: FusionAccess resource created"
exit 0
true
