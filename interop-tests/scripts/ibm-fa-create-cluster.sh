#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare clusterName="${STORAGE_SCALE_CLUSTER_NAME:-ibm-spectrum-scale}"
declare namespace="ibm-spectrum-scale"

# Check namespace exists
if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "FAIL: namespace ${namespace} does not exist -- create namespaces first" >&2
    exit 1
fi

# Apply Storage Scale Cluster CR
cat <<EOF | oc apply -f -
apiVersion: scale.spectrum.ibm.com/v1beta1
kind: Cluster
metadata:
  name: ${clusterName}
  namespace: ${namespace}
spec:
  daemon:
    clusterNameOverride: ${clusterName}
    nodeSelector:
      scale: "true"
EOF
echo "Applied Storage Scale Cluster CR ${clusterName} in ${namespace}"

# Wait for cluster to be available (poll up to 60 times, 30s apart = 30m)
declare -i maxPolls=60
declare -i poll=0
declare clusterStatus=""
echo "Waiting for Storage Scale cluster ${clusterName} to be available (up to ${maxPolls} polls)..."
while [[ ${poll} -lt ${maxPolls} ]]; do
    clusterStatus=$(oc get cluster "${clusterName}" -n "${namespace}" \
        -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null) || true
    if [[ "${clusterStatus}" == "True" ]]; then
        echo "Storage Scale cluster ${clusterName} is Available"
        break
    fi
    echo "Poll ${poll}/${maxPolls}: cluster status Available=${clusterStatus:-Pending}"
    sleep 30
    poll+=1
done

if [[ "${clusterStatus}" != "True" ]]; then
    echo "FAIL: Storage Scale cluster ${clusterName} did not become Available after ${maxPolls} polls (status: ${clusterStatus:-NotFound})" >&2
    if [[ -n "${ARTIFACT_DIR:-}" ]]; then
        oc get cluster "${clusterName}" -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/storage-scale-cluster.yaml" 2>/dev/null || true
    fi
    exit 1
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get cluster "${clusterName}" -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/storage-scale-cluster.yaml" 2>/dev/null || true
fi

echo "PASS: Storage Scale cluster created"
exit 0
true
