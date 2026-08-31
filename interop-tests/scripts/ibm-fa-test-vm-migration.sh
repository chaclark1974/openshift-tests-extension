#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare cnvNamespace="openshift-cnv"
declare testNS="ibm-fa-vm-migration-test"
declare scaleSC="${IBM_FA_SCALE_SC:-ibm-spectrum-scale-sc}"
declare vmName="test-vm-migration"
declare dvName="test-dv-migration"

# Check CNV is available
declare hcoAvailable
hcoAvailable=$(oc get hyperconverged -n "${cnvNamespace}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [[ "${hcoAvailable}" != "True" ]]; then
    echo "FAIL: HyperConverged CR is not Available (status: ${hcoAvailable})" >&2
    exit 1
fi

# Need at least 2 schedulable worker nodes for migration
declare workerCount
workerCount=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${workerCount}" -lt 2 ]]; then
    echo "SKIP: live migration requires at least 2 worker nodes (found ${workerCount})" >&2
    exit 2
fi

# Cleanup function
cleanup() {
    echo "Cleaning up test resources..."
    oc delete virtualmachineinstancemigration "${vmName}-migration" -n "${testNS}" --ignore-not-found --wait=false 2>/dev/null || true
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

# Create a DataVolume with Scale storage (RWX for live migration)
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
    - ReadWriteMany
    resources:
      requests:
        storage: 1Gi
    storageClassName: ${scaleSC}
EOF
echo "Created DataVolume ${dvName} with RWX access"

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

# Create a VirtualMachine with live migration enabled
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
      evictionStrategy: LiveMigrate
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

# Record source node
declare sourceNode
sourceNode=$(oc get vmi "${vmName}" -n "${testNS}" -o jsonpath='{.status.nodeName}' 2>/dev/null)
echo "VM ${vmName} is running on node: ${sourceNode}"

# Create VirtualMachineInstanceMigration CR
cat <<EOF | oc apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachineInstanceMigration
metadata:
  name: ${vmName}-migration
  namespace: ${testNS}
spec:
  vmiName: ${vmName}
EOF
echo "Created VirtualMachineInstanceMigration for ${vmName}"

# Wait for migration to complete (up to 10m)
declare -i migTimeout=600
elapsed=0
declare migPhase=""
echo "Waiting for migration to complete (timeout 10m)..."
while [[ ${elapsed} -lt ${migTimeout} ]]; do
    migPhase=$(oc get virtualmachineinstancemigration "${vmName}-migration" -n "${testNS}" \
        -o jsonpath='{.status.phase}' 2>/dev/null) || true
    if [[ "${migPhase}" == "Succeeded" ]]; then
        echo "Migration succeeded"
        break
    fi
    if [[ "${migPhase}" == "Failed" ]]; then
        echo "FAIL: migration failed" >&2
        if [[ -n "${ARTIFACT_DIR:-}" ]]; then
            oc get virtualmachineinstancemigration "${vmName}-migration" -n "${testNS}" -o yaml > "${ARTIFACT_DIR}/migration-status.yaml" 2>/dev/null || true
        fi
        exit 1
    fi
    sleep 15
    elapsed+=15
done

if [[ "${migPhase}" != "Succeeded" ]]; then
    echo "FAIL: migration did not complete within 10m (phase: ${migPhase:-Unknown})" >&2
    exit 1
fi

# Verify VM is on a different node
declare targetNode
targetNode=$(oc get vmi "${vmName}" -n "${testNS}" -o jsonpath='{.status.nodeName}' 2>/dev/null)
echo "VM ${vmName} is now running on node: ${targetNode}"

if [[ "${sourceNode}" == "${targetNode}" ]]; then
    echo "FAIL: VM did not migrate to a different node (still on ${sourceNode})" >&2
    exit 1
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get virtualmachineinstancemigration "${vmName}-migration" -n "${testNS}" -o yaml > "${ARTIFACT_DIR}/migration-result.yaml" 2>/dev/null || true
fi

echo "PASS: VM live migration passed"
exit 0
true
