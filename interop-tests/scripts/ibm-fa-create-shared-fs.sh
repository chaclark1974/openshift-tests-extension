#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare namespace="ibm-spectrum-scale"
declare fsName="${IBM_FA_SHARED_FS_NAME:-shared-filesystem}"

# Skip if Storage Scale cluster is not available
declare clusterReady
clusterReady=$(oc get scalecluster -n "${namespace}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
if [[ "${clusterReady}" != "True" ]]; then
    echo "SKIP: Storage Scale cluster not available (status: ${clusterReady})" >&2
    exit 2
fi

# Apply shared Filesystem CR
cat <<EOF | oc apply -f -
apiVersion: scale.spectrum.ibm.com/v1beta1
kind: Filesystem
metadata:
  name: ${fsName}
  namespace: ${namespace}
spec:
  type: shared
  automaticMountOption: true
EOF
echo "Applied shared Filesystem CR ${fsName}"

# Wait for filesystem to be ready (timeout 30m)
declare -i timeout=1800
declare -i elapsed=0
declare fsCondition=""
echo "Waiting for shared Filesystem ${fsName} to become Available (timeout 30m)..."
while [[ ${elapsed} -lt ${timeout} ]]; do
    fsCondition=$(oc get filesystem "${fsName}" -n "${namespace}" \
        -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null) || true
    if [[ "${fsCondition}" == "True" ]]; then
        echo "Filesystem ${fsName} is Available"
        break
    fi
    sleep 30
    elapsed+=30
done

if [[ "${fsCondition}" != "True" ]]; then
    echo "FAIL: shared Filesystem ${fsName} did not become Available within 30m (condition: ${fsCondition:-NotFound})" >&2
    if [[ -n "${ARTIFACT_DIR:-}" ]]; then
        oc get filesystem "${fsName}" -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/shared-filesystem-status.yaml" 2>/dev/null || true
    fi
    exit 1
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get filesystem "${fsName}" -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/shared-filesystem.yaml" 2>/dev/null || true
fi

echo "PASS: Shared filesystem created"
exit 0
true
