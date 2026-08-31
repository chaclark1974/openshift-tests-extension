#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare namespace="ibm-spectrum-scale"
declare -i failures=0

# Check that ibm-spectrum-scale namespace exists
if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "FAIL: namespace ${namespace} does not exist" >&2
    exit 1
fi

# Check Storage Scale cluster CR exists
declare clusterCount
clusterCount=$(oc get scalecluster -n "${namespace}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${clusterCount}" -eq 0 ]]; then
    echo "FAIL: no ScaleCluster CR found in ${namespace}" >&2
    exit 1
fi
echo "OK: ScaleCluster CR found"

# Check cluster status is healthy/available
declare clusterReady
clusterReady=$(oc get scalecluster -n "${namespace}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
if [[ "${clusterReady}" != "True" ]]; then
    echo "FAIL: ScaleCluster is not Ready (status: ${clusterReady})" >&2
    failures+=1
else
    echo "OK: ScaleCluster is Ready"
fi

declare clusterAvailable
clusterAvailable=$(oc get scalecluster -n "${namespace}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [[ "${clusterAvailable}" != "True" ]]; then
    echo "FAIL: ScaleCluster is not Available (status: ${clusterAvailable})" >&2
    failures+=1
else
    echo "OK: ScaleCluster is Available"
fi

# Check daemon pods are running in ibm-spectrum-scale namespace
declare -i runningPods=0
while IFS= read -r line; do
    declare podName podStatus
    podName=$(echo "${line}" | awk '{print $1}')
    podStatus=$(echo "${line}" | awk '{print $3}')
    if [[ "${podStatus}" == "Running" ]]; then
        runningPods+=1
    fi
done < <(oc get pods -n "${namespace}" --no-headers 2>/dev/null | grep -E "daemon|scale" || true)

declare totalPods
totalPods=$(oc get pods -n "${namespace}" --no-headers --field-selector=status.phase=Running 2>/dev/null | wc -l | tr -d ' ')
if [[ "${totalPods}" -eq 0 ]]; then
    echo "FAIL: no running pods found in ${namespace}" >&2
    failures+=1
else
    echo "OK: ${totalPods} pod(s) running in ${namespace}"
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get scalecluster -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/scalecluster.yaml" 2>/dev/null || true
    oc get pods -n "${namespace}" -o wide > "${ARTIFACT_DIR}/scale-pods.txt" 2>/dev/null || true
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: ${failures} Storage Scale cluster health check(s) failed" >&2
    exit 1
fi

echo "PASS: Storage Scale cluster healthy (${totalPods} pods running)"
exit 0
true
