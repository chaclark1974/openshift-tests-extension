#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare cnvNamespace="openshift-cnv"
declare scaleSC="${IBM_FA_SCALE_SC:-ibm-spectrum-scale-sc}"
declare -i failures=0

# Check HyperConverged CR exists in openshift-cnv
declare hcoCount
hcoCount=$(oc get hyperconverged -n "${cnvNamespace}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${hcoCount}" -eq 0 ]]; then
    echo "FAIL: no HyperConverged CR found in ${cnvNamespace} -- CNV not installed" >&2
    exit 1
fi
echo "OK: HyperConverged CR found in ${cnvNamespace}"

# Check StorageClass for Scale exists
if ! oc get storageclass "${scaleSC}" &>/dev/null; then
    echo "FAIL: StorageClass ${scaleSC} does not exist" >&2
    exit 1
fi
echo "OK: StorageClass ${scaleSC} exists"

# Configure CDI to use Scale storage class for scratch space
declare cdiName
cdiName=$(oc get cdi --no-headers 2>/dev/null | awk '{print $1}' | head -1)
if [[ -n "${cdiName}" ]]; then
    oc patch cdi "${cdiName}" --type merge -p "{\"spec\":{\"config\":{\"scratchSpaceStorageClass\":\"${scaleSC}\"}}}" 2>/dev/null || true
    echo "OK: CDI scratch space storage class set to ${scaleSC}"
else
    echo "FAIL: CDI resource not found" >&2
    failures+=1
fi

# Annotate the StorageClass as default for CNV workloads
oc annotate storageclass "${scaleSC}" \
    storageclass.kubevirt.io/is-default-virt-class=true \
    --overwrite 2>/dev/null || true
echo "OK: StorageClass ${scaleSC} annotated as default for CNV"

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get hyperconverged -n "${cnvNamespace}" -o yaml > "${ARTIFACT_DIR}/hyperconverged-cnv-storage.yaml" 2>/dev/null || true
    oc get storageclass "${scaleSC}" -o yaml > "${ARTIFACT_DIR}/scale-storageclass.yaml" 2>/dev/null || true
    oc get cdi -o yaml > "${ARTIFACT_DIR}/cdi-cnv-storage.yaml" 2>/dev/null || true
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: ${failures} CNV storage configuration step(s) failed" >&2
    exit 1
fi

echo "PASS: CNV configured to use Scale shared storage"
exit 0
true
