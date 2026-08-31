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
    echo "FAIL: namespace ${namespace} does not exist -- OpenShift Virtualization not installed" >&2
    exit 1
fi

# Check HyperConverged CR is Available
declare hcoAvailable
hcoAvailable=$(oc get hyperconverged -n "${namespace}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [[ "${hcoAvailable}" != "True" ]]; then
    echo "FAIL: HyperConverged CR is not Available (status: ${hcoAvailable})" >&2
    failures+=1
else
    echo "OK: HyperConverged CR is Available"
fi

# Check all pods in openshift-cnv namespace are Running or Completed
declare -i badPods=0
while IFS= read -r line; do
    declare podName podStatus
    podName=$(echo "${line}" | awk '{print $1}')
    podStatus=$(echo "${line}" | awk '{print $3}')
    if [[ "${podStatus}" != "Running" && "${podStatus}" != "Completed" ]]; then
        badPods+=1
        echo "  Not healthy: ${podName} (${podStatus})" >&2
    fi
done < <(oc get pods -n "${namespace}" --no-headers 2>/dev/null)

if [[ ${badPods} -gt 0 ]]; then
    echo "FAIL: ${badPods} pod(s) in ${namespace} are not Running/Completed" >&2
    failures+=1
else
    declare totalPods
    totalPods=$(oc get pods -n "${namespace}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "OK: all ${totalPods} pods in ${namespace} are Running or Completed"
fi

# Check VirtualMachineInstancetype resources exist
declare vmitCount
vmitCount=$(oc get virtualmachineinstancetype --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
declare vmcitCount
vmcitCount=$(oc get virtualmachineclusterinstancetype --no-headers 2>/dev/null | wc -l | tr -d ' ')
declare totalInstancetypes=$((vmitCount + vmcitCount))
if [[ ${totalInstancetypes} -eq 0 ]]; then
    echo "FAIL: no VirtualMachineInstancetype or VirtualMachineClusterInstancetype resources found" >&2
    failures+=1
else
    echo "OK: ${vmitCount} VirtualMachineInstancetype(s), ${vmcitCount} VirtualMachineClusterInstancetype(s) found"
fi

# Check default storage class is set
declare defaultSC
defaultSC=$(oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "")
if [[ -z "${defaultSC}" ]]; then
    echo "FAIL: no default storage class is set" >&2
    failures+=1
else
    echo "OK: default storage class is ${defaultSC}"
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get hyperconverged -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/hyperconverged.yaml" 2>/dev/null || true
    oc get pods -n "${namespace}" -o wide > "${ARTIFACT_DIR}/cnv-pods.txt" 2>/dev/null || true
    oc get virtualmachineclusterinstancetype -o yaml > "${ARTIFACT_DIR}/vmclusterinstancetypes.yaml" 2>/dev/null || true
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: ${failures} OpenShift Virtualization check(s) failed" >&2
    exit 1
fi

echo "PASS: OpenShift Virtualization verified -- HyperConverged Available, all pods healthy, instancetypes present, default SC set"
exit 0
true
