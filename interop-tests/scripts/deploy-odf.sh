#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

if [[ -z "${ODF_VERSION_MAJOR_MINOR:-}" ]]; then
    echo "SKIP: ODF_VERSION_MAJOR_MINOR not set" >&2
    exit 2
fi

declare namespace="openshift-storage"
declare channel="stable-${ODF_VERSION_MAJOR_MINOR}"
declare clusterName="${ODF_STORAGE_CLUSTER_NAME:-ocs-storagecluster}"

# Create namespace
if ! oc get namespace "${namespace}" &>/dev/null; then
    oc create namespace "${namespace}"
    echo "Created namespace ${namespace}"
else
    echo "Namespace ${namespace} already exists"
fi

# Create OperatorGroup
if ! oc get operatorgroup -n "${namespace}" --no-headers 2>/dev/null | grep -q .; then
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-storage-operatorgroup
  namespace: ${namespace}
spec:
  targetNamespaces:
  - ${namespace}
EOF
    echo "Created OperatorGroup in ${namespace}"
else
    echo "OperatorGroup already exists in ${namespace}"
fi

# Create Subscription for odf-operator
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: odf-operator
  namespace: ${namespace}
spec:
  channel: "${channel}"
  installPlanApproval: Automatic
  name: odf-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
echo "Created Subscription for odf-operator on channel ${channel}"

# Wait for CSV to succeed
declare -i csvTimeout=600
declare -i elapsed=0
declare csvPhase=""
echo "Waiting for odf-operator CSV to reach Succeeded phase (timeout ${csvTimeout}s)..."
while [[ ${elapsed} -lt ${csvTimeout} ]]; do
    declare csvName
    csvName=$(oc get csv -n "${namespace}" --no-headers 2>/dev/null | grep "odf-operator" | head -1 | awk '{print $1}') || true
    if [[ -n "${csvName}" ]]; then
        csvPhase=$(oc get csv "${csvName}" -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null) || true
        if [[ "${csvPhase}" == "Succeeded" ]]; then
            echo "CSV ${csvName} is Succeeded"
            break
        fi
    fi
    sleep 15
    elapsed+=15
done

if [[ "${csvPhase}" != "Succeeded" ]]; then
    echo "FAIL: odf-operator CSV did not reach Succeeded phase within ${csvTimeout}s (phase: ${csvPhase:-NotFound})" >&2
    exit 1
fi

# Wait for ocs-operator deployment
declare -i deployTimeout=300
elapsed=0
echo "Waiting for ocs-operator deployment (timeout ${deployTimeout}s)..."
while [[ ${elapsed} -lt ${deployTimeout} ]]; do
    declare readyReplicas
    readyReplicas=$(oc get deployment ocs-operator -n "${namespace}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null) || true
    if [[ "${readyReplicas}" -gt 0 ]] 2>/dev/null; then
        echo "ocs-operator deployment is ready (${readyReplicas} replicas)"
        break
    fi
    sleep 10
    elapsed+=10
done

if ! oc get deployment ocs-operator -n "${namespace}" &>/dev/null; then
    echo "FAIL: ocs-operator deployment not found after ${deployTimeout}s" >&2
    exit 1
fi

# Label worker nodes for ODF storage
declare -i labelCount=0
while IFS= read -r nodeName; do
    if [[ -n "${nodeName}" ]]; then
        oc label node "${nodeName}" cluster.ocs.openshift.io/openshift-storage="" --overwrite 2>/dev/null || true
        labelCount+=1
    fi
done < <(oc get nodes -l node-role.kubernetes.io/worker --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null)

if [[ ${labelCount} -eq 0 ]]; then
    echo "FAIL: no worker nodes found to label for ODF storage" >&2
    exit 1
fi
echo "Labeled ${labelCount} worker nodes for ODF storage"

# Create StorageCluster
cat <<EOF | oc apply -f -
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  name: ${clusterName}
  namespace: ${namespace}
spec:
  manageNodes: false
  monDataDirHostPath: /var/lib/rook
  storageDeviceSets:
  - count: 1
    dataPVCTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 512Gi
        storageClassName: gp3-csi
        volumeMode: Block
    name: ocs-deviceset
    placement: {}
    portable: true
    replica: 3
    resources: {}
EOF
echo "Created StorageCluster ${clusterName}"

# Wait for StorageCluster to become Available (timeout 30m)
declare -i scTimeout=1800
elapsed=0
declare scCondition=""
echo "Waiting for StorageCluster ${clusterName} to become Available (timeout 30m)..."
while [[ ${elapsed} -lt ${scTimeout} ]]; do
    scCondition=$(oc get storagecluster "${clusterName}" -n "${namespace}" \
        -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null) || true
    if [[ "${scCondition}" == "True" ]]; then
        echo "StorageCluster ${clusterName} is Available"
        break
    fi
    sleep 30
    elapsed+=30
done

if [[ "${scCondition}" != "True" ]]; then
    echo "FAIL: StorageCluster ${clusterName} did not become Available within 30m (condition: ${scCondition:-NotFound})" >&2
    if [[ -n "${ARTIFACT_DIR:-}" ]]; then
        oc get storagecluster "${clusterName}" -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/storagecluster-status.yaml" 2>/dev/null || true
    fi
    exit 1
fi

# Set default storage class
declare defaultSC="${clusterName}-ceph-rbd"
# Remove default annotation from all existing storage classes
while IFS= read -r scName; do
    if [[ -n "${scName}" ]]; then
        oc annotate storageclass "${scName}" storageclass.kubernetes.io/is-default-class- --overwrite 2>/dev/null || true
    fi
done < <(oc get storageclass -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n')

# Set the new default
if ! oc get storageclass "${defaultSC}" &>/dev/null; then
    echo "FAIL: storage class ${defaultSC} not found" >&2
    exit 1
fi
oc annotate storageclass "${defaultSC}" storageclass.kubernetes.io/is-default-class=true --overwrite
echo "Set ${defaultSC} as default storage class"

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get storagecluster -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/storagecluster-final.yaml" 2>/dev/null || true
    oc get csv -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/odf-csv.yaml" 2>/dev/null || true
fi

echo "PASS: ODF deployed successfully"
exit 0
true
