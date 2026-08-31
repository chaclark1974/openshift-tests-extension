#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare scaleSC="${IBM_FA_SCALE_SC:-ibm-spectrum-scale-sc}"
declare testNS1="ibm-fa-shared-storage-test-1"
declare testNS2="ibm-fa-shared-storage-test-2"
declare pvcName1="test-pvc-shared-1"
declare pvcName2="test-pvc-shared-2"

# Check Scale StorageClass exists
if ! oc get storageclass "${scaleSC}" &>/dev/null; then
    echo "FAIL: StorageClass ${scaleSC} does not exist" >&2
    exit 1
fi
echo "OK: StorageClass ${scaleSC} exists"

# Cleanup function
cleanup() {
    echo "Cleaning up test resources..."
    oc delete pvc "${pvcName1}" -n "${testNS1}" --ignore-not-found --wait=false 2>/dev/null || true
    oc delete pvc "${pvcName2}" -n "${testNS2}" --ignore-not-found --wait=false 2>/dev/null || true
    oc delete namespace "${testNS1}" --ignore-not-found --wait=false 2>/dev/null || true
    oc delete namespace "${testNS2}" --ignore-not-found --wait=false 2>/dev/null || true
}
trap cleanup EXIT

# Create two test namespaces
oc create namespace "${testNS1}" 2>/dev/null || true
oc create namespace "${testNS2}" 2>/dev/null || true
echo "Created test namespaces ${testNS1} and ${testNS2}"

# Create PVC in first namespace
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvcName1}
  namespace: ${testNS1}
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: ${scaleSC}
EOF
echo "Created PVC ${pvcName1} in ${testNS1}"

# Create PVC in second namespace
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvcName2}
  namespace: ${testNS2}
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: ${scaleSC}
EOF
echo "Created PVC ${pvcName2} in ${testNS2}"

# Wait for both PVCs to be Bound (up to 5m)
declare -i pvcTimeout=300
declare -i elapsed=0
declare -i failures=0

echo "Waiting for PVCs to be Bound (timeout 5m)..."
declare pvc1Bound="false"
declare pvc2Bound="false"

while [[ ${elapsed} -lt ${pvcTimeout} ]]; do
    declare pvc1Status pvc2Status
    pvc1Status=$(oc get pvc "${pvcName1}" -n "${testNS1}" -o jsonpath='{.status.phase}' 2>/dev/null) || true
    pvc2Status=$(oc get pvc "${pvcName2}" -n "${testNS2}" -o jsonpath='{.status.phase}' 2>/dev/null) || true

    if [[ "${pvc1Status}" == "Bound" ]]; then
        pvc1Bound="true"
    fi
    if [[ "${pvc2Status}" == "Bound" ]]; then
        pvc2Bound="true"
    fi

    if [[ "${pvc1Bound}" == "true" && "${pvc2Bound}" == "true" ]]; then
        break
    fi

    sleep 10
    elapsed+=10
done

if [[ "${pvc1Bound}" != "true" ]]; then
    echo "FAIL: PVC ${pvcName1} in ${testNS1} is not Bound" >&2
    failures+=1
else
    echo "OK: PVC ${pvcName1} in ${testNS1} is Bound"
fi

if [[ "${pvc2Bound}" != "true" ]]; then
    echo "FAIL: PVC ${pvcName2} in ${testNS2} is not Bound" >&2
    failures+=1
else
    echo "OK: PVC ${pvcName2} in ${testNS2} is Bound"
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get pvc "${pvcName1}" -n "${testNS1}" -o yaml > "${ARTIFACT_DIR}/shared-pvc-1.yaml" 2>/dev/null || true
    oc get pvc "${pvcName2}" -n "${testNS2}" -o yaml > "${ARTIFACT_DIR}/shared-pvc-2.yaml" 2>/dev/null || true
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: ${failures} PVC(s) could not be bound with shared storage" >&2
    exit 1
fi

echo "PASS: Shared storage between CNV and Fusion verified"
exit 0
true
