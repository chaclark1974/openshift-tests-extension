#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare policyRepoDir="${POLICY_COLLECTION_DIR:-}"
if [[ -z "${policyRepoDir}" ]]; then
    echo "POLICY_COLLECTION_DIR not set, skipping" >&2
    exit 2
fi

declare pgDir="${policyRepoDir}/policygenerator"
if [[ ! -d "${pgDir}" ]]; then
    echo "FAIL: policygenerator directory not found at ${pgDir}" >&2
    exit 1
fi

declare kustomizationCount
kustomizationCount=$(find "${pgDir}" \( -name 'kustomization.yaml' -o -name 'kustomization.yml' \) 2>/dev/null | wc -l | tr -d ' ')

declare policyGeneratorCount
policyGeneratorCount=$(find "${pgDir}" -name '*.yaml' -print0 2>/dev/null | xargs -0 grep -l 'PolicyGenerator' 2>/dev/null | wc -l | tr -d ' ')

if [[ ${kustomizationCount} -eq 0 && ${policyGeneratorCount} -eq 0 ]]; then
    echo "FAIL: no kustomization or PolicyGenerator files found in ${pgDir}" >&2
    exit 1
fi

echo "PASS: policygenerator directory has ${kustomizationCount} kustomization files and ${policyGeneratorCount} PolicyGenerator references"
exit 0
true
