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

# Check CNV operator is deployed (HyperConverged Available)
declare hcoAvailable
hcoAvailable=$(oc get hyperconverged -n "${namespace}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [[ "${hcoAvailable}" != "True" ]]; then
    echo "FAIL: HyperConverged CR is not Available (status: ${hcoAvailable})" >&2
    failures+=1
else
    echo "OK: HyperConverged CR is Available"
fi

# Check that CDI (Containerized Data Importer) is healthy
declare cdiAvailable
cdiAvailable=$(oc get cdi -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [[ "${cdiAvailable}" != "True" ]]; then
    echo "FAIL: CDI is not Available (status: ${cdiAvailable})" >&2
    failures+=1
else
    echo "OK: CDI is Available"
fi

# Check that virt-api is responding (oc get virtualmachines should not error)
if ! oc get virtualmachines --all-namespaces &>/dev/null; then
    echo "FAIL: virt-api is not responding (oc get virtualmachines failed)" >&2
    failures+=1
else
    declare vmCount
    vmCount=$(oc get virtualmachines --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "OK: virt-api is responding (${vmCount} VMs across all namespaces)"
fi

# Check at least one DataImportCron exists
declare dicCount
dicCount=$(oc get dataimportcron --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${dicCount}" -eq 0 ]]; then
    echo "FAIL: no DataImportCron resources found" >&2
    failures+=1
else
    echo "OK: ${dicCount} DataImportCron resource(s) found"
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get hyperconverged -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/hyperconverged.yaml" 2>/dev/null || true
    oc get cdi -o yaml > "${ARTIFACT_DIR}/cdi.yaml" 2>/dev/null || true
    oc get dataimportcron --all-namespaces -o yaml > "${ARTIFACT_DIR}/dataimportcrons.yaml" 2>/dev/null || true
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: ${failures} CNV smoke check(s) failed" >&2
    exit 1
fi

echo "PASS: CNV smoke checks passed -- HyperConverged Available, CDI healthy, virt-api responding, DataImportCrons present"
exit 0
true
