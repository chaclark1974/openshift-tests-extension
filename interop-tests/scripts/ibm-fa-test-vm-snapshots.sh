#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare cnvNamespace="openshift-cnv"
declare testNS="ibm-fa-vm-snapshot-test"
declare scaleSC="${IBM_FA_SCALE_SC:-ibm-spectrum-scale-sc}"
declare vmName="test-vm-snapshot"
declare dvName="test-dv-snapshot"
declare snapshotName="test-vm-snapshot-snap"

# Check VolumeSnapshotClass exists for Scale CSI
declare vscCount
vscCount=$(oc get volumesnapshotclass --no-headers 2>/dev/null | grep -i "scale\|spectrumscale\|ibm" | wc -l | tr -d ' ')
if [[ "${vscCount}" -eq 0 ]]; then
    echo "SKIP: no VolumeSnapshotClass found for Scale CSI" >&2
    exit 2
fi

declare vscName
vscName=$(oc get volumesnapshotclass --no-headers 2>/dev/null | grep -i "scale\|spectrumscale\|ibm" | head -1 | awk '{print $1}')
echo "OK: VolumeSnapshotClass ${vscName} found for Scale CSI"

# Check CNV is available
declare hcoAvailable
hcoAvailable=$(oc get hyperconverged -n "${cnvNamespace}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [[ "${hcoAvailable}" != "True" ]]; then
    echo "FAIL: HyperConverged CR is not Available (status: ${hcoAvailable})" >&2
    exit 1
fi

# Cleanup function
cleanup() {
    echo "Cleaning up test resources..."
    oc delete virtualmachinesnapshot "${snapshotName}" -n "${testNS}" --ignore-not-found --wait=false 2>/dev/null || true
    oc delete vm "${vmName}" -n "${testNS}" --ignore-not-found --wait=false 2>/dev/null || true
    oc delete vmi "${vmName}" -n "${testNS}" --ignore-not-found --wait=false 2>/dev/null || true
    oc delete dv "${dvName}" -n "${testNS}" --ignore-not-found --wait=false 2>/dev/null || true
    oc delete namespace "${testNS}" --ignore-not-found --wait=false 2>/dev/null || true
}
trap cleanup EXIT

# Create test namespace
oc create namespace "${testNS}" 2>/dev/null || true

# Determine a boot source URL
declare sourceURL="${IBM_FA_TEST_IMAGE_URL:-https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img}"

# Create a DataVolume with Scale storage
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

# Create a VirtualMachine
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
    exit 1
fi

# Create VirtualMachineSnapshot
cat <<EOF | oc apply -f -
apiVersion: snapshot.kubevirt.io/v1beta1
kind: VirtualMachineSnapshot
metadata:
  name: ${snapshotName}
  namespace: ${testNS}
spec:
  source:
    apiGroup: kubevirt.io
    kind: VirtualMachine
    name: ${vmName}
EOF
echo "Created VirtualMachineSnapshot ${snapshotName}"

# Wait for snapshot to be Ready (up to 5m)
declare -i snapTimeout=300
elapsed=0
declare snapReady=""
echo "Waiting for VirtualMachineSnapshot ${snapshotName} to be Ready (timeout 5m)..."
while [[ ${elapsed} -lt ${snapTimeout} ]]; do
    snapReady=$(oc get virtualmachinesnapshot "${snapshotName}" -n "${testNS}" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null) || true
    if [[ "${snapReady}" == "True" ]]; then
        echo "VirtualMachineSnapshot ${snapshotName} is Ready"
        break
    fi
    sleep 10
    elapsed+=10
done

if [[ "${snapReady}" != "True" ]]; then
    echo "FAIL: VirtualMachineSnapshot ${snapshotName} did not become Ready within 5m" >&2
    if [[ -n "${ARTIFACT_DIR:-}" ]]; then
        oc get virtualmachinesnapshot "${snapshotName}" -n "${testNS}" -o yaml > "${ARTIFACT_DIR}/vm-snapshot-status.yaml" 2>/dev/null || true
    fi
    exit 1
fi

# Verify snapshot resource exists
if ! oc get virtualmachinesnapshot "${snapshotName}" -n "${testNS}" &>/dev/null; then
    echo "FAIL: VirtualMachineSnapshot ${snapshotName} not found" >&2
    exit 1
fi
echo "OK: VirtualMachineSnapshot ${snapshotName} verified"

# Delete snapshot (cleanup verifies delete works)
oc delete virtualmachinesnapshot "${snapshotName}" -n "${testNS}" --wait=true --timeout=60s
echo "OK: VirtualMachineSnapshot ${snapshotName} deleted"

echo "PASS: VM snapshot create/delete passed"
exit 0
true
