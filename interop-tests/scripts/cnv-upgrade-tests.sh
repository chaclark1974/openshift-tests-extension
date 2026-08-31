#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

if [[ -z "${CNV_TARGET_VERSION:-}" ]]; then
    echo "SKIP: CNV_TARGET_VERSION not set" >&2
    exit 2
fi

declare -i failures=0

# ---- Check HyperConverged CR exists ----
echo "Checking HyperConverged CR..."
declare hcName
hcName=$(oc get hyperconverged -n openshift-cnv -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -z "${hcName}" ]]; then
    echo "FAIL: HyperConverged CR not found in openshift-cnv namespace" >&2
    exit 1
fi
echo "  OK: HyperConverged CR found: ${hcName}"

# ---- Get current CNV version ----
echo "Checking CNV version..."
declare currentVersion
currentVersion=$(oc get hyperconverged "${hcName}" -n openshift-cnv -o jsonpath='{.status.versions[?(@.name=="operator")].version}' 2>/dev/null || echo "")
if [[ -z "${currentVersion}" ]]; then
    # Fallback: try observedVersion
    currentVersion=$(oc get hyperconverged "${hcName}" -n openshift-cnv -o jsonpath='{.status.observedGeneration}' 2>/dev/null || echo "unknown")
    currentVersion=$(oc get hyperconverged "${hcName}" -n openshift-cnv -o jsonpath='{.status.operatorVersion}' 2>/dev/null || echo "${currentVersion}")
fi
echo "  Current CNV version: ${currentVersion}"
echo "  Target CNV version: ${CNV_TARGET_VERSION}"

if [[ "${currentVersion}" != "${CNV_TARGET_VERSION}" ]]; then
    echo "FAIL: CNV version mismatch (current=${currentVersion}, target=${CNV_TARGET_VERSION})" >&2
    exit 1
fi

echo "CNV version matches target, validating components..."

# ---- Check all pods in openshift-cnv ----
echo "Checking pods in openshift-cnv namespace..."
declare -i podFailures=0
while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    declare podName podStatus
    podName=$(echo "${line}" | awk '{print $1}')
    podStatus=$(echo "${line}" | awk '{print $3}')
    if [[ "${podStatus}" != "Running" && "${podStatus}" != "Completed" && "${podStatus}" != "Succeeded" ]]; then
        podFailures+=1
        echo "  Pod not healthy: ${podName} (${podStatus})" >&2
    fi
done < <(oc get pods -n openshift-cnv --no-headers 2>/dev/null)

if [[ ${podFailures} -gt 0 ]]; then
    failures+=1
    echo "  ${podFailures} unhealthy pod(s) in openshift-cnv" >&2
else
    declare podCount
    podCount=$(oc get pods -n openshift-cnv --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "  OK: ${podCount} pods healthy in openshift-cnv"
fi

# ---- Check HyperConverged is Available ----
echo "Checking HyperConverged availability..."
declare hcAvailable
hcAvailable=$(oc get hyperconverged "${hcName}" -n openshift-cnv -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")
if [[ "${hcAvailable}" != "True" ]]; then
    failures+=1
    echo "  HyperConverged not Available (status=${hcAvailable})" >&2
else
    echo "  OK: HyperConverged is Available"
fi

# ---- Check KubeVirt CR is Available ----
echo "Checking KubeVirt CR..."
declare kvAvailable
kvAvailable=$(oc get kubevirt -n openshift-cnv -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")
if [[ "${kvAvailable}" != "True" ]]; then
    failures+=1
    echo "  KubeVirt CR not Available (status=${kvAvailable})" >&2
else
    echo "  OK: KubeVirt CR is Available"
fi

# ---- Check CDI is healthy ----
echo "Checking CDI..."
declare cdiAvailable
cdiAvailable=$(oc get cdi -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")
if [[ "${cdiAvailable}" != "True" ]]; then
    failures+=1
    echo "  CDI not Available (status=${cdiAvailable})" >&2
else
    echo "  OK: CDI is Available"
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: CNV upgrade validation found ${failures} issue(s)" >&2
    exit 1
fi

echo "PASS: CNV upgrade validation passed"
exit 0
true
