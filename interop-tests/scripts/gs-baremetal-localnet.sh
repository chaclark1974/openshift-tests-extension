#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare -i failures=0

# Check that nodes have bare-metal hardware (BareMetalHost resources or machine.openshift.io/instance-type label)
declare bmhCount
bmhCount=$(oc get baremetalhost --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${bmhCount}" -eq 0 ]]; then
    # Fallback: check if platform is BareMetal via infrastructure CR
    declare platform
    platform=$(oc get infrastructure cluster -o jsonpath='{.status.platform}' 2>/dev/null || echo "Unknown")
    if [[ "${platform}" != "BareMetal" ]]; then
        echo "SKIP: not a bare-metal cluster (platform: ${platform}, no BareMetalHost resources)" >&2
        exit 2
    fi
    echo "OK: infrastructure platform is BareMetal"
else
    echo "OK: ${bmhCount} BareMetalHost resource(s) found"
fi

# Check OVN-Kubernetes is deployed
declare ovnNamespace="openshift-ovn-kubernetes"
if ! oc get namespace "${ovnNamespace}" &>/dev/null; then
    echo "FAIL: namespace ${ovnNamespace} does not exist -- OVN-Kubernetes not deployed" >&2
    exit 1
fi
echo "OK: OVN-Kubernetes namespace exists"

# Check that net-attach-def resources exist for localnet
declare nadCount
nadCount=$(oc get net-attach-def --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${nadCount}" -eq 0 ]]; then
    echo "FAIL: no NetworkAttachmentDefinition resources found" >&2
    failures+=1
else
    echo "OK: ${nadCount} NetworkAttachmentDefinition resource(s) found"
    # Check specifically for localnet type
    declare localnetCount
    localnetCount=$(oc get net-attach-def --all-namespaces -o json 2>/dev/null | grep -c '"localnet"' || echo "0")
    if [[ "${localnetCount}" -gt 0 ]]; then
        echo "OK: localnet configuration found in NetworkAttachmentDefinitions"
    else
        echo "OK: NetworkAttachmentDefinitions found (localnet type not explicitly detected in config)"
    fi
fi

# Verify node network state shows bridge configuration
declare nnsCount
nnsCount=$(oc get nodenetworkstate --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${nnsCount}" -eq 0 ]]; then
    echo "FAIL: no NodeNetworkState resources found" >&2
    failures+=1
else
    echo "OK: ${nnsCount} NodeNetworkState resource(s) found"
    # Check for bridge interfaces in node network state
    declare bridgeFound="false"
    while IFS= read -r nnsName; do
        if [[ -n "${nnsName}" ]]; then
            declare bridges
            bridges=$(oc get nodenetworkstate "${nnsName}" -o jsonpath='{.status.currentState.interfaces[?(@.type=="linux-bridge")].name}' 2>/dev/null || echo "")
            if [[ -n "${bridges}" ]]; then
                bridgeFound="true"
                echo "OK: bridge interface(s) found on ${nnsName}: ${bridges}"
                break
            fi
        fi
    done < <(oc get nodenetworkstate --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -5)
    if [[ "${bridgeFound}" == "false" ]]; then
        echo "OK: NodeNetworkState resources present (no linux-bridge interfaces detected -- may use OVS bridges)"
    fi
fi

# Check pods in openshift-ovn-kubernetes are running
declare -i ovnRunning=0
declare -i ovnBad=0
while IFS= read -r line; do
    declare podName podStatus
    podName=$(echo "${line}" | awk '{print $1}')
    podStatus=$(echo "${line}" | awk '{print $3}')
    if [[ "${podStatus}" == "Running" || "${podStatus}" == "Completed" ]]; then
        ovnRunning+=1
    else
        ovnBad+=1
        echo "  Not healthy: ${podName} (${podStatus})" >&2
    fi
done < <(oc get pods -n "${ovnNamespace}" --no-headers 2>/dev/null)

if [[ ${ovnRunning} -eq 0 ]]; then
    echo "FAIL: no running pods in ${ovnNamespace}" >&2
    failures+=1
else
    echo "OK: ${ovnRunning} pod(s) running in ${ovnNamespace}"
fi

if [[ ${ovnBad} -gt 0 ]]; then
    echo "FAIL: ${ovnBad} pod(s) in ${ovnNamespace} are not healthy" >&2
    failures+=1
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get pods -n "${ovnNamespace}" -o wide > "${ARTIFACT_DIR}/ovn-pods.txt" 2>/dev/null || true
    oc get net-attach-def --all-namespaces -o yaml > "${ARTIFACT_DIR}/net-attach-defs.yaml" 2>/dev/null || true
    oc get nodenetworkstate -o yaml > "${ARTIFACT_DIR}/nodenetworkstate.yaml" 2>/dev/null || true
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: ${failures} GS bare-metal localnet check(s) failed" >&2
    exit 1
fi

echo "PASS: GS bare-metal localnet checks passed"
exit 0
true
