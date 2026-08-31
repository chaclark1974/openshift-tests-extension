#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare policyCount
policyCount=$(oc get policies.policy.open-cluster-management.io -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${policyCount}" -eq 0 ]]; then
    echo "WARN: no ACM policies found on the hub — policies may not be deployed yet" >&2
    exit 2
fi

declare -i compliant=0
declare -i noncompliant=0
declare -i pending=0

while IFS= read -r line; do
    declare ns name status
    ns=$(echo "${line}" | awk '{print $1}')
    name=$(echo "${line}" | awk '{print $2}')
    status=$(echo "${line}" | awk '{print $NF}')
    case "${status}" in
        Compliant)
            compliant+=1
            ;;
        NonCompliant)
            noncompliant+=1
            echo "  NonCompliant: ${ns}/${name}" >&2
            ;;
        *)
            pending+=1
            echo "  Pending: ${ns}/${name} (${status})" >&2
            ;;
    esac
done < <(oc get policies.policy.open-cluster-management.io -A --no-headers 2>/dev/null)

echo "Policy compliance: ${compliant} compliant, ${noncompliant} non-compliant, ${pending} pending (${policyCount} total)"

if [[ ${noncompliant} -gt 0 ]]; then
    echo "FAIL: ${noncompliant} policies are NonCompliant" >&2
    exit 1
fi

if [[ ${pending} -gt 0 ]]; then
    echo "WARN: ${pending} policies still pending" >&2
fi

echo "PASS: all ${compliant} evaluated policies are Compliant"
exit 0
true
