#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare policyRepoDir="${POLICY_COLLECTION_DIR:-}"
if [[ -z "${policyRepoDir}" ]]; then
    echo "POLICY_COLLECTION_DIR not set, skipping" >&2
    exit 2
fi

declare categoryDir="${policyRepoDir}/stable/CA-Security-Assessment-and-Authorization"
if [[ ! -d "${categoryDir}" ]]; then
    echo "FAIL: CA-Security-Assessment-and-Authorization directory not found" >&2
    exit 1
fi

declare expectedPolicy="policy-compliance-operator-install.yaml"
if [[ ! -f "${categoryDir}/${expectedPolicy}" ]]; then
    echo "FAIL: ${expectedPolicy} not found — compliance operator install policy is required" >&2
    exit 1
fi

if ! grep -q 'kind: Policy' "${categoryDir}/${expectedPolicy}"; then
    echo "FAIL: ${expectedPolicy} does not contain a Policy resource" >&2
    exit 1
fi

if ! grep -q 'compliance-operator' "${categoryDir}/${expectedPolicy}"; then
    echo "FAIL: ${expectedPolicy} does not reference compliance-operator" >&2
    exit 1
fi

echo "PASS: CA-Security-Assessment-and-Authorization compliance operator install policy present and valid"
exit 0
true
