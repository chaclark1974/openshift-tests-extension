#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare profileCount
profileCount=$(oc get storageprofiles --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${profileCount}" -eq 0 ]]; then
    echo "FAIL: no StorageProfiles found — CDI storage integration not configured" >&2
    exit 1
fi

declare scCount
scCount=$(oc get storageclasses --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${scCount}" -eq 0 ]]; then
    echo "FAIL: no StorageClasses found on cluster" >&2
    exit 1
fi

declare defaultSc
defaultSc=$(oc get storageclasses -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "")
if [[ -z "${defaultSc}" ]]; then
    echo "WARN: no default StorageClass set" >&2
fi

echo "PASS: ${profileCount} storage profiles and ${scCount} storage classes found (default: ${defaultSc:-none})"
exit 0
true
