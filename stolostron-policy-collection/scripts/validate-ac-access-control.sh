#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare policyRepoDir="${POLICY_COLLECTION_DIR:-}"
if [[ -z "${policyRepoDir}" ]]; then
    echo "POLICY_COLLECTION_DIR not set, skipping" >&2
    exit 2
fi

declare categoryDir="${policyRepoDir}/stable/AC-Access-Control"
if [[ ! -d "${categoryDir}" ]]; then
    echo "FAIL: AC-Access-Control directory not found at ${categoryDir}" >&2
    exit 1
fi

declare -a expectedPolicies=(
    "policy-role.yaml"
    "policy-rolebinding.yaml"
)

declare -i missing=0
for policy in "${expectedPolicies[@]}"; do
    if [[ ! -f "${categoryDir}/${policy}" ]]; then
        echo "FAIL: expected policy ${policy} not found" >&2
        missing+=1
    fi
done

if [[ ${missing} -gt 0 ]]; then
    echo "FAIL: ${missing} expected AC policies missing" >&2
    exit 1
fi

for policy in "${expectedPolicies[@]}"; do
    if ! grep -q 'kind: Policy' "${categoryDir}/${policy}"; then
        echo "FAIL: ${policy} does not contain a Policy resource" >&2
        exit 1
    fi
    if ! grep -q 'apiVersion: policy.open-cluster-management.io' "${categoryDir}/${policy}"; then
        echo "FAIL: ${policy} does not use policy.open-cluster-management.io API" >&2
        exit 1
    fi
done

echo "PASS: AC-Access-Control policies (policy-role, policy-rolebinding) present and well-formed"
exit 0
true
