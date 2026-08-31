#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare namespace="ibm-spectrum-scale"
declare fsName="${IBM_FA_EBS_FS_NAME:-ebs-filesystem}"

# Skip if Storage Scale cluster is not ready
declare clusterStatus
clusterStatus=$(oc get scalecluster -n "${namespace}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
if [[ "${clusterStatus}" != "True" ]]; then
    echo "SKIP: Storage Scale cluster not ready (status: ${clusterStatus})" >&2
    exit 2
fi

# Apply Filesystem CR for EBS-backed storage
cat <<EOF | oc apply -f -
apiVersion: scale.spectrum.ibm.com/v1beta1
kind: Filesystem
metadata:
  name: ${fsName}
  namespace: ${namespace}
spec:
  type: ebs
  automaticMountOption: true
  localDiskSets:
  - diskType: localDisk
    diskNames:
    - localdisk-nvme2n1
    - localdisk-nvme3n1
    - localdisk-nvme4n1
EOF
echo "Applied Filesystem CR ${fsName}"

# Wait for filesystem to be available (timeout 30m)
declare -i timeout=1800
declare -i elapsed=0
declare fsCondition=""
echo "Waiting for Filesystem ${fsName} to become Available (timeout 30m)..."
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
    echo "FAIL: Filesystem ${fsName} did not become Available within 30m (condition: ${fsCondition:-NotFound})" >&2
    if [[ -n "${ARTIFACT_DIR:-}" ]]; then
        oc get filesystem "${fsName}" -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/ebs-filesystem-status.yaml" 2>/dev/null || true
    fi
    exit 1
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get filesystem "${fsName}" -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/ebs-filesystem.yaml" 2>/dev/null || true
fi

echo "PASS: EBS filesystem created"
exit 0
true
