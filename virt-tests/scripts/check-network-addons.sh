#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi

declare cnaPhase
cnaPhase=$(oc get networkaddonsconfig cluster -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [[ "${cnaPhase}" == "NotFound" ]]; then
    echo "FAIL: NetworkAddonsConfig 'cluster' not found" >&2
    exit 1
fi

if [[ "${cnaPhase}" != "True" ]]; then
    echo "FAIL: NetworkAddonsConfig is not Available (status: ${cnaPhase})" >&2
    exit 1
fi

declare nadCount
nadCount=$(oc get net-attach-def --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')

echo "PASS: NetworkAddonsConfig is available, ${nadCount} NetworkAttachmentDefinitions found"
exit 0
true
