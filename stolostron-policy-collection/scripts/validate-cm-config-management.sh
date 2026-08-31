#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare policyRepoDir="${POLICY_COLLECTION_DIR:-}"
if [[ -z "${policyRepoDir}" ]]; then
    echo "POLICY_COLLECTION_DIR not set, skipping" >&2
    exit 2
fi

declare categoryDir="${policyRepoDir}/stable/CM-Configuration-Management"
if [[ ! -d "${categoryDir}" ]]; then
    echo "FAIL: CM-Configuration-Management directory not found" >&2
    exit 1
fi

declare -a expectedPolicies=(
    "policy-namespace.yaml"
    "policy-pod.yaml"
    "policy-compliance-operator-cis-scan.yaml"
    "policy-compliance-operator-e8-scan.yaml"
    "policy-gatekeeper-operator-downstream.yaml"
)

declare -i missing=0
for policy in "${expectedPolicies[@]}"; do
    if [[ ! -f "${categoryDir}/${policy}" ]]; then
        echo "WARN: expected policy ${policy} not found" >&2
        missing+=1
    fi
done

declare fileCount
fileCount=$(find "${categoryDir}" -name '*.yaml' | wc -l | tr -d ' ')
if [[ "${fileCount}" -eq 0 ]]; then
    echo "FAIL: no YAML files found in CM-Configuration-Management" >&2
    exit 1
fi

declare -i invalidCount=0
while IFS= read -r yamlFile; do
    if ! grep -q 'kind: Policy' "${yamlFile}" 2>/dev/null; then
        if ! grep -q 'kind: Application\|kind: AppProject\|kind: ArgoCD' "${yamlFile}" 2>/dev/null; then
            echo "WARN: ${yamlFile} does not contain a recognized resource kind" >&2
            invalidCount+=1
        fi
    fi
done < <(find "${categoryDir}" -name '*.yaml')

echo "PASS: CM-Configuration-Management has ${fileCount} policies, ${missing} optional policies missing, ${invalidCount} warnings"
exit 0
true
