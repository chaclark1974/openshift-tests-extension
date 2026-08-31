#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare -a expectedOperators=(
    "advanced-cluster-management"
    "rhacs-operator"
    "quay-operator"
    "quay-bridge-operator"
    "compliance-operator"
    "odf-operator"
    "ocs-operator"
)

declare -i foundCount=0
declare -i missingCount=0

for operator in "${expectedOperators[@]}"; do
    declare csvName
    csvName=$(oc get csv --all-namespaces -o jsonpath="{.items[?(@.metadata.name=~\"${operator}.*\")].metadata.name}" 2>/dev/null | awk '{print $1}')
    if [[ -z "${csvName}" ]]; then
        csvName=$(oc get csv --all-namespaces --no-headers 2>/dev/null | grep "${operator}" | head -1 | awk '{print $2}')
    fi

    if [[ -n "${csvName}" ]]; then
        echo "  Found: ${operator} (${csvName})"
        foundCount+=1
    else
        echo "  Missing: ${operator}" >&2
        missingCount+=1
    fi
done

if [[ ${missingCount} -gt 0 ]]; then
    echo "FAIL: ${missingCount} OPP operators not found via CSV" >&2
    exit 1
fi

echo "PASS: all ${foundCount} OPP operator CSVs are installed"
exit 0
true
