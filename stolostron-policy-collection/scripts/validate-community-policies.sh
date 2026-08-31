#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare policyRepoDir="${POLICY_COLLECTION_DIR:-}"
if [[ -z "${policyRepoDir}" ]]; then
    echo "POLICY_COLLECTION_DIR not set, skipping" >&2
    exit 2
fi

declare communityDir="${policyRepoDir}/community"
if [[ ! -d "${communityDir}" ]]; then
    echo "FAIL: community directory not found at ${communityDir}" >&2
    exit 1
fi

declare categoryCount
categoryCount=$(find "${communityDir}" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [[ "${categoryCount}" -eq 0 ]]; then
    echo "FAIL: no policy categories found under community/" >&2
    exit 1
fi

declare yamlCount
yamlCount=$(find "${communityDir}" -name '*.yaml' -not -name 'kustomization*' | wc -l | tr -d ' ')
if [[ "${yamlCount}" -eq 0 ]]; then
    echo "FAIL: no YAML policy files found under community/" >&2
    exit 1
fi

declare -i invalidCount=0
while IFS= read -r yamlFile; do
    if ! python3 -c "import yaml; list(yaml.safe_load_all(open('${yamlFile}')))" 2>/dev/null; then
        echo "WARN: invalid YAML syntax in ${yamlFile}" >&2
        invalidCount+=1
    fi
done < <(find "${communityDir}" -name '*.yaml' -not -name 'kustomization*')

if [[ ${invalidCount} -gt 0 ]]; then
    echo "WARN: ${invalidCount} community policy files have YAML syntax issues" >&2
fi

echo "PASS: community policies have ${categoryCount} categories with ${yamlCount} policy files (${invalidCount} warnings)"
exit 0
true
