#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare policyRepoDir="${POLICY_COLLECTION_DIR:-}"
if [[ -z "${policyRepoDir}" ]]; then
    echo "POLICY_COLLECTION_DIR not set, skipping" >&2
    exit 2
fi

declare categoryDir="${policyRepoDir}/stable/SI-System-and-Information-Integrity"
if [[ ! -d "${categoryDir}" ]]; then
    echo "FAIL: SI-System-and-Information-Integrity directory not found" >&2
    exit 1
fi

declare expectedPolicy="policy-imagemanifestvuln.yaml"
if [[ ! -f "${categoryDir}/${expectedPolicy}" ]]; then
    echo "FAIL: ${expectedPolicy} not found — image vulnerability detection policy required" >&2
    exit 1
fi

if ! grep -q 'kind: Policy' "${categoryDir}/${expectedPolicy}"; then
    echo "FAIL: ${expectedPolicy} does not contain a Policy resource" >&2
    exit 1
fi

if ! grep -q 'imagemanifestvuln\|ImageManifestVuln\|container-security-operator' "${categoryDir}/${expectedPolicy}"; then
    echo "FAIL: ${expectedPolicy} does not reference image vulnerability scanning" >&2
    exit 1
fi

echo "PASS: SI-System-and-Information-Integrity image vulnerability policy present and valid"
exit 0
true
