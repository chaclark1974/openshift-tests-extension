#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare namespace="openshift-cnv"

if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "FAIL: namespace ${namespace} does not exist" >&2
    exit 1
fi

declare podCount
podCount=$(oc get pods -n "${namespace}" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${podCount}" -eq 0 ]]; then
    echo "FAIL: no running pods in ${namespace}" >&2
    exit 1
fi

declare hcoStatus
hcoStatus=$(oc get hyperconverged kubevirt-hyperconverged -n "${namespace}" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [[ "${hcoStatus}" != "True" ]]; then
    echo "FAIL: HyperConverged operator not available (status: ${hcoStatus})" >&2
    exit 1
fi

echo "PASS: CNV operator is running in ${namespace} with ${podCount} pods"
exit 0
true
