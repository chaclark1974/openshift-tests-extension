#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare namespace="openshift-storage"

if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "FAIL: namespace ${namespace} does not exist — ODF not installed" >&2
    exit 1
fi

declare csvName
csvName=$(oc get csv -n "${namespace}" --no-headers 2>/dev/null | grep "odf-operator" | head -1 | awk '{print $1}')
if [[ -z "${csvName}" ]]; then
    csvName=$(oc get csv -n "${namespace}" --no-headers 2>/dev/null | grep "ocs-operator" | head -1 | awk '{print $1}')
fi
if [[ -z "${csvName}" ]]; then
    echo "FAIL: no ODF/OCS operator CSV found in ${namespace}" >&2
    exit 1
fi

declare csvPhase
csvPhase=$(oc get csv "${csvName}" -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
if [[ "${csvPhase}" != "Succeeded" ]]; then
    echo "FAIL: ODF operator CSV ${csvName} is not Succeeded (phase: ${csvPhase})" >&2
    exit 1
fi

declare scPhase
scPhase=$(oc get storagecluster -n "${namespace}" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [[ "${scPhase}" != "Ready" ]]; then
    echo "FAIL: StorageCluster is not Ready (phase: ${scPhase})" >&2
    exit 1
fi

echo "PASS: ODF is deployed — ${csvName} (${csvPhase}), StorageCluster Ready"
exit 0
true
