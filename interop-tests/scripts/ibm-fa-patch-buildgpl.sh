#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare namespace="ibm-spectrum-scale"
declare configMapName="buildgpl"

# Check if buildgpl ConfigMap exists
if ! oc get configmap "${configMapName}" -n "${namespace}" &>/dev/null; then
    echo "SKIP: buildgpl ConfigMap not found in ${namespace}" >&2
    exit 2
fi

echo "Found buildgpl ConfigMap in ${namespace}"

# Patch the buildgpl ConfigMap to fix RHCOS compatibility issues.
# The RHCOS kernel build environment differs from standard RHEL, and the
# default buildgpl script may fail. This patch adjusts the build flags
# to work on RHCOS nodes.
oc patch configmap "${configMapName}" -n "${namespace}" --type merge \
    -p '{"data":{"RHCOS_COMPAT":"true"}}'
echo "Patched buildgpl ConfigMap with RHCOS compatibility flag"

# Verify the patch was applied
declare patchValue
patchValue=$(oc get configmap "${configMapName}" -n "${namespace}" \
    -o jsonpath='{.data.RHCOS_COMPAT}' 2>/dev/null) || true
if [[ "${patchValue}" != "true" ]]; then
    echo "FAIL: buildgpl patch verification failed (RHCOS_COMPAT=${patchValue:-not set})" >&2
    exit 1
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    oc get configmap "${configMapName}" -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/buildgpl-configmap.yaml" 2>/dev/null || true
fi

echo "PASS: buildgpl patched for RHCOS compatibility"
exit 0
true
