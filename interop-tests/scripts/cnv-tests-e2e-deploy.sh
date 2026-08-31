#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare namespace="openshift-cnv"
declare -i failures=0

# Check that the CNV namespace exists
if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "FAIL: namespace ${namespace} does not exist -- CNV not installed" >&2
    exit 1
fi

# Check that HyperConverged CR exists and is Available
declare hcoAvailable
hcoAvailable=$(oc get hyperconverged -n "${namespace}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [[ "${hcoAvailable}" != "True" ]]; then
    echo "FAIL: HyperConverged CR is not Available (status: ${hcoAvailable})" >&2
    failures+=1
else
    echo "OK: HyperConverged CR is Available"
fi

# Check that virt-operator, virt-controller, virt-handler pods are running
declare -a requiredPods=("virt-operator" "virt-controller" "virt-handler")
for podPrefix in "${requiredPods[@]}"; do
    declare podCount
    podCount=$(oc get pods -n "${namespace}" --no-headers --field-selector=status.phase=Running 2>/dev/null | grep "^${podPrefix}" | wc -l | tr -d ' ')
    if [[ "${podCount}" -eq 0 ]]; then
        echo "FAIL: no running ${podPrefix} pods found in ${namespace}" >&2
        failures+=1
    else
        echo "OK: ${podCount} ${podPrefix} pod(s) running"
    fi
done

# Check that KubeVirt CR is Available
declare kvAvailable
kvAvailable=$(oc get kubevirt -n "${namespace}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [[ "${kvAvailable}" != "True" ]]; then
    echo "FAIL: KubeVirt CR is not Available (status: ${kvAvailable})" >&2
    failures+=1
else
    echo "OK: KubeVirt CR is Available"
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get hyperconverged -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/hyperconverged.yaml" 2>/dev/null || true
    oc get kubevirt -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/kubevirt.yaml" 2>/dev/null || true
    oc get pods -n "${namespace}" -o wide > "${ARTIFACT_DIR}/cnv-pods.txt" 2>/dev/null || true
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: ${failures} CNV deployment check(s) failed" >&2
    exit 1
fi

echo "PASS: CNV deployment verified -- HyperConverged Available, core pods running, KubeVirt Available"
exit 0
true
