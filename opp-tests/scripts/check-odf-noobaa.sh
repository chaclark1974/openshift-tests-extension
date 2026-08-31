#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare namespace="openshift-storage"

if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "FAIL: namespace ${namespace} does not exist" >&2
    exit 1
fi

declare noobaaPhase
noobaaPhase=$(oc get noobaa noobaa -n "${namespace}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [[ "${noobaaPhase}" == "NotFound" ]]; then
    echo "FAIL: NooBaa CR not found in ${namespace}" >&2
    exit 1
fi

if [[ "${noobaaPhase}" != "Ready" ]]; then
    echo "FAIL: NooBaa is not Ready (phase: ${noobaaPhase})" >&2
    exit 1
fi

declare s3Endpoint
s3Endpoint=$(oc get noobaa noobaa -n "${namespace}" -o jsonpath='{.status.services.serviceS3.externalDNS[0]}' 2>/dev/null || echo "")

echo "PASS: NooBaa is Ready (S3 endpoint: ${s3Endpoint:-internal-only})"
exit 0
true
