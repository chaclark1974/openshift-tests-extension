#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare namespace="${CDI_NAMESPACE:-openshift-cnv}"

declare cdiPhase
cdiPhase=$(oc get cdi -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [[ "${cdiPhase}" != "Deployed" ]]; then
    echo "FAIL: CDI is not in Deployed phase (status: ${cdiPhase})" >&2
    exit 1
fi

declare readyReplicas
readyReplicas=$(oc get deployment cdi-deployment -n "${namespace}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "${readyReplicas}" -eq 0 ]]; then
    echo "FAIL: cdi-deployment has no ready replicas" >&2
    exit 1
fi

echo "PASS: CDI is deployed (phase: ${cdiPhase}, cdi-deployment: ${readyReplicas} ready)"
exit 0
true
