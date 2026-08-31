#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare namespace="openshift-storage"
declare -i failures=0

# Check that the namespace exists
if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "FAIL: namespace ${namespace} does not exist -- ODF/OCS not installed" >&2
    exit 1
fi

# Check that the odf-operator CSV exists and is Succeeded
declare csvName
csvName=$(oc get csv -n "${namespace}" --no-headers 2>/dev/null | grep "odf-operator" | head -1 | awk '{print $1}') || true
if [[ -z "${csvName}" ]]; then
    csvName=$(oc get csv -n "${namespace}" --no-headers 2>/dev/null | grep "ocs-operator" | head -1 | awk '{print $1}') || true
fi
if [[ -z "${csvName}" ]]; then
    echo "FAIL: no ODF/OCS operator CSV found in ${namespace}" >&2
    failures+=1
else
    declare csvPhase
    csvPhase=$(oc get csv "${csvName}" -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "${csvPhase}" != "Succeeded" ]]; then
        echo "FAIL: operator CSV ${csvName} is not Succeeded (phase: ${csvPhase})" >&2
        failures+=1
    else
        echo "OK: operator CSV ${csvName} is Succeeded"
    fi
fi

# Check StorageCluster is Ready
declare scPhase
scPhase=$(oc get storagecluster -n "${namespace}" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [[ "${scPhase}" != "Ready" ]]; then
    echo "FAIL: StorageCluster is not Ready (phase: ${scPhase})" >&2
    failures+=1
else
    declare scName
    scName=$(oc get storagecluster -n "${namespace}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "unknown")
    echo "OK: StorageCluster ${scName} is Ready"
fi

# Check CephCluster health
declare cephHealth
cephHealth=$(oc get cephcluster -n "${namespace}" -o jsonpath='{.items[0].status.ceph.health}' 2>/dev/null || echo "NotFound")
if [[ "${cephHealth}" == "NotFound" ]]; then
    echo "FAIL: no CephCluster found in ${namespace}" >&2
    failures+=1
elif [[ "${cephHealth}" != "HEALTH_OK" ]]; then
    echo "FAIL: CephCluster health is ${cephHealth} (expected HEALTH_OK)" >&2
    failures+=1
else
    echo "OK: CephCluster health is ${cephHealth}"
fi

# Check that default storage class contains "ceph"
declare defaultSC
defaultSC=$(oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "")
if [[ -z "${defaultSC}" ]]; then
    echo "FAIL: no default storage class is set" >&2
    failures+=1
elif [[ "${defaultSC}" != *ceph* ]]; then
    echo "FAIL: default storage class '${defaultSC}' does not contain 'ceph'" >&2
    failures+=1
else
    echo "OK: default storage class is ${defaultSC}"
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get storagecluster -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/storagecluster.yaml" 2>/dev/null || true
    oc get cephcluster -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/cephcluster.yaml" 2>/dev/null || true
    oc get csv -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/odf-csv.yaml" 2>/dev/null || true
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: ${failures} OCS check(s) failed" >&2
    exit 1
fi

echo "PASS: OCS is operational -- CSV Succeeded, StorageCluster Ready, CephCluster healthy, default SC set"
exit 0
true
