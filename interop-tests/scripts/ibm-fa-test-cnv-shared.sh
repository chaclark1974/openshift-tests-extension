#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare cnvNamespace="openshift-cnv"
declare testNS="ibm-fa-cnv-shared-test"
declare scaleSC="${IBM_FA_SCALE_SC:-ibm-spectrum-scale-sc}"
declare dvName="test-dv-scale"
declare vmName="test-vm-scale"

# Check CNV is available
declare hcoAvailable
hcoAvailable=$(oc get hyperconverged -n "${cnvNamespace}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [[ "${hcoAvailable}" != "True" ]]; then
    echo "FAIL: HyperConverged CR is not Available (status: ${hcoAvailable})" >&2
    exit 1
fi
echo "OK: HyperConverged CR is Available"

# Cleanup function
cleanup() {
    echo "Cleaning up test resources..."
    oc delete vm "${vmName}" -n "${testNS}" --ignore-not-found --wait=false 2>/dev/null || true
    oc delete vmi "${vmName}" -n "${testNS}" --ignore-not-found --wait=false 2>/dev/null || true
    oc delete dv "${dvName}" -n "${testNS}" --ignore-not-found --wait=false 2>/dev/null || true
    oc delete namespace "${testNS}" --ignore-not-found --wait=false 2>/dev/null || true
}
trap cleanup EXIT

# Create test namespace
oc create namespace "${testNS}" 2>/dev/null || true
echo "Created test namespace ${testNS}"

# Determine a boot source URL -- prefer a lightweight image
declare sourceURL="${IBM_FA_TEST_IMAGE_URL:-https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img}"

# Create a DataVolume using Scale storage class
cat <<EOF | oc apply -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: ${dvName}
  namespace: ${testNS}
spec:
  source:
    http:
      url: "${sourceURL}"
  storage:
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 1Gi
    storageClassName: ${scaleSC}
EOF
echo "Created DataVolume ${dvName}"

# Wait for DataVolume to succeed (up to 10m)
declare -i dvTimeout=600
declare -i elapsed=0
declare dvPhase=""
echo "Waiting for DataVolume ${dvName} to succeed (timeout 10m)..."
while [[ ${elapsed} -lt ${dvTimeout} ]]; do
    dvPhase=$(oc get dv "${dvName}" -n "${testNS}" -o jsonpath='{.status.phase}' 2>/dev/null) || true
    if [[ "${dvPhase}" == "Succeeded" ]]; then
        echo "DataVolume ${dvName} succeeded"
        break
    fi
    if [[ "${dvPhase}" == "Failed" ]]; then
        echo "FAIL: DataVolume ${dvName} failed" >&2
        exit 1
    fi
    sleep 15
    elapsed+=15
done

if [[ "${dvPhase}" != "Succeeded" ]]; then
    echo "FAIL: DataVolume ${dvName} did not succeed within 10m (phase: ${dvPhase:-Unknown})" >&2
    exit 1
fi

# Create a VirtualMachine using the DataVolume
cat <<EOF | oc apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${vmName}
  namespace: ${testNS}
spec:
  running: true
  template:
    spec:
      domain:
        resources:
          requests:
            memory: 256Mi
        devices:
          disks:
          - name: rootdisk
            disk:
              bus: virtio
      volumes:
      - name: rootdisk
        dataVolume:
          name: ${dvName}
EOF
echo "Created VirtualMachine ${vmName}"

# Wait for VM to be Running (up to 5m)
declare -i vmTimeout=300
elapsed=0
declare vmStatus=""
echo "Waiting for VM ${vmName} to be Running (timeout 5m)..."
while [[ ${elapsed} -lt ${vmTimeout} ]]; do
    vmStatus=$(oc get vmi "${vmName}" -n "${testNS}" -o jsonpath='{.status.phase}' 2>/dev/null) || true
    if [[ "${vmStatus}" == "Running" ]]; then
        echo "VM ${vmName} is Running"
        break
    fi
    sleep 10
    elapsed+=10
done

if [[ "${vmStatus}" != "Running" ]]; then
    echo "FAIL: VM ${vmName} did not reach Running within 5m (status: ${vmStatus:-Unknown})" >&2
    if [[ -n "${ARTIFACT_DIR:-}" ]]; then
        oc get vm "${vmName}" -n "${testNS}" -o yaml > "${ARTIFACT_DIR}/cnv-shared-vm.yaml" 2>/dev/null || true
        oc get dv "${dvName}" -n "${testNS}" -o yaml > "${ARTIFACT_DIR}/cnv-shared-dv.yaml" 2>/dev/null || true
    fi
    exit 1
fi

echo "PASS: CNV VM with Scale shared storage works"
exit 0
true
