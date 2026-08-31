#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

if [[ -z "${CNV_TARGET_MAJOR_MINOR:-}" ]]; then
    echo "SKIP: CNV_TARGET_MAJOR_MINOR not set" >&2
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

# ---- Check CNV operator subscription ----
echo "Checking CNV operator subscription..."
declare subName
subName=$(oc get subscription -n openshift-cnv --no-headers 2>/dev/null | awk '{print $1}' | head -1 || true)
if [[ -z "${subName}" ]]; then
    failures+=1
    echo "  Subscription not found in openshift-cnv" >&2
else
    declare subState
    subState=$(oc get subscription "${subName}" -n openshift-cnv -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")
    echo "  OK: Subscription found: ${subName} (state=${subState})"
fi

# ---- Check ODF storage class ----
echo "Checking ODF storage class..."
declare storageClass=""
if oc get storageclass ocs-storagecluster-ceph-rbd-virtualization &>/dev/null; then
    storageClass="ocs-storagecluster-ceph-rbd-virtualization"
else
    # Fall back to default storage class
    storageClass=$(oc get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null | awk '{print $1}' || true)
fi

if [[ -z "${storageClass}" ]]; then
    failures+=1
    echo "  No suitable storage class found (no ocs-storagecluster-ceph-rbd-virtualization or default)" >&2
else
    echo "  OK: Storage class: ${storageClass}"
fi

# ---- Check DataImportCrons ----
echo "Checking DataImportCrons..."
declare dicCount
dicCount=$(oc get dataimportcrons --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${dicCount}" -eq 0 ]]; then
    echo "  WARN: no DataImportCrons found" >&2
else
    declare -i dicNotReady=0
    while IFS= read -r line; do
        declare dicNamespace dicName dicUpToDate
        dicNamespace=$(echo "${line}" | awk '{print $1}')
        dicName=$(echo "${line}" | awk '{print $2}')
        # Check if DataImportCron is UpToDate
        dicUpToDate=$(oc get dataimportcron "${dicName}" -n "${dicNamespace}" -o jsonpath='{.status.conditions[?(@.type=="UpToDate")].status}' 2>/dev/null || echo "Unknown")
        if [[ "${dicUpToDate}" != "True" ]]; then
            dicNotReady+=1
            echo "  DataImportCron not UpToDate: ${dicNamespace}/${dicName}" >&2
        fi
    done < <(oc get dataimportcrons --all-namespaces --no-headers 2>/dev/null)

    if [[ ${dicNotReady} -gt 0 ]]; then
        failures+=1
        echo "  ${dicNotReady} DataImportCron(s) not UpToDate" >&2
    else
        echo "  OK: ${dicCount} DataImportCron(s) are UpToDate"
    fi
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: CNV upgrade preparation found ${failures} issue(s)" >&2
    exit 1
fi

echo "PASS: Cluster prepared for CNV upgrade"
exit 0
true
