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
    echo "WARN: no policies found on the hub — apply policies before running propagation tests" >&2
    exit 2
fi

declare -i noncompliant=0
declare -i compliant=0
declare -i pending=0

while IFS= read -r line; do
    declare status
    status=$(echo "${line}" | awk '{print $NF}')
    case "${status}" in
        Compliant)    compliant+=1 ;;
        NonCompliant) noncompliant+=1 ;;
        *)            pending+=1 ;;
    esac
done < <(oc get policies.policy.open-cluster-management.io -A --no-headers 2>/dev/null)

echo "Policy status summary: ${compliant} compliant, ${noncompliant} non-compliant, ${pending} pending"
echo "Total policies found: ${policyCount}"

if [[ ${noncompliant} -gt 0 ]]; then
    echo "WARN: ${noncompliant} policies are non-compliant" >&2
fi

echo "PASS: policy propagation check complete — ${policyCount} policies found on hub"
exit 0
true
