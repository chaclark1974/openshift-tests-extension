#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare policyRepoDir="${POLICY_COLLECTION_DIR:-}"
if [[ -z "${policyRepoDir}" ]]; then
    echo "POLICY_COLLECTION_DIR not set, skipping" >&2
    exit 2
fi

if [[ ! -d "${policyRepoDir}/stable" ]]; then
    echo "FAIL: ${policyRepoDir}/stable directory not found" >&2
    exit 1
fi

declare -i totalFiles=0
declare -i failedFiles=0

while IFS= read -r -d '' yamlFile; do
    totalFiles+=1
    if ! python3 -c "import yaml; yaml.safe_load_all(open('${yamlFile}'))" 2>/dev/null; then
        if ! oc apply --dry-run=client -f "${yamlFile}" &>/dev/null 2>&1; then
            echo "WARN: invalid YAML: ${yamlFile}" >&2
            failedFiles+=1
        fi
    fi
done < <(find "${policyRepoDir}/stable" -name '*.yaml' -print0)

if [[ ${totalFiles} -eq 0 ]]; then
    echo "FAIL: no YAML files found under ${policyRepoDir}/stable" >&2
    exit 1
fi

if [[ ${failedFiles} -gt 0 ]]; then
    echo "FAIL: ${failedFiles}/${totalFiles} stable policy YAML files have syntax errors" >&2
    exit 1
fi

echo "PASS: all ${totalFiles} stable policy YAML files are valid"
exit 0
true
