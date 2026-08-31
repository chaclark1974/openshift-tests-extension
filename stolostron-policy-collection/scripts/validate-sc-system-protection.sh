#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare policyRepoDir="${POLICY_COLLECTION_DIR:-}"
if [[ -z "${policyRepoDir}" ]]; then
    echo "POLICY_COLLECTION_DIR not set, skipping" >&2
    exit 2
fi

declare categoryDir="${policyRepoDir}/stable/SC-System-and-Communications-Protection"
if [[ ! -d "${categoryDir}" ]]; then
    echo "FAIL: SC-System-and-Communications-Protection directory not found" >&2
    exit 1
fi

declare -a expectedPolicies=(
    "policy-certificate.yaml"
    "policy-etcdencryption.yaml"
    "policy-limitmemory.yaml"
)

declare -i missing=0
for policy in "${expectedPolicies[@]}"; do
    if [[ ! -f "${categoryDir}/${policy}" ]]; then
        echo "WARN: expected policy ${policy} not found" >&2
        missing+=1
    fi
done

if [[ -f "${categoryDir}/policy-certificate.yaml" ]]; then
    if ! grep -q 'CertificatePolicy' "${categoryDir}/policy-certificate.yaml"; then
        echo "FAIL: policy-certificate.yaml does not reference CertificatePolicy kind" >&2
        exit 1
    fi
fi

if [[ -f "${categoryDir}/policy-etcdencryption.yaml" ]]; then
    if ! grep -q 'etcd' "${categoryDir}/policy-etcdencryption.yaml"; then
        echo "FAIL: policy-etcdencryption.yaml does not reference etcd" >&2
        exit 1
    fi
fi

declare fileCount
fileCount=$(find "${categoryDir}" -name '*.yaml' | wc -l | tr -d ' ')
echo "PASS: SC-System-and-Communications-Protection has ${fileCount} policies (${missing} optional missing)"
exit 0
true
