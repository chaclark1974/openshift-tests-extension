#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare -i failures=0

# Check for key CRDs
declare -a requiredCRDs=(
    "localvolumes.local.storage.openshift.io"
    "fusionserviceinstances.fusion.ibm.com"
)

for crd in "${requiredCRDs[@]}"; do
    if oc get crd "${crd}" &>/dev/null; then
        echo "OK: CRD ${crd} exists"
    else
        echo "FAIL: CRD ${crd} not found" >&2
        failures+=1
    fi
done

# List all CRDs matching IBM/Fusion/Spectrum patterns
echo ""
echo "--- IBM/Fusion/Spectrum CRDs found on cluster ---"
oc get crd --no-headers 2>/dev/null \
    | awk '{print $1}' \
    | grep -iE '(ibm|fusion|spectrum)' || echo "(none found)"
echo "---"

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get crd --no-headers 2>/dev/null \
        | awk '{print $1}' \
        | grep -iE '(ibm|fusion|spectrum)' > "${ARTIFACT_DIR}/ibm-fa-crds.txt" 2>/dev/null || true
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: ${failures} required CRD(s) not found" >&2
    exit 1
fi

echo "PASS: All required IBM Storage Scale CRDs are available"
exit 0
true
