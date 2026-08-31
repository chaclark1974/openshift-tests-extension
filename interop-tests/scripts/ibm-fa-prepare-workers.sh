#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare -a requiredDirs=(
    "/var/lib/firmware"
    "/var/mmfs/etc"
    "/var/mmfs/var"
    "/var/mmfs/tmp"
)

declare -i failures=0
declare -i nodeCount=0

while IFS= read -r nodeName; do
    if [[ -z "${nodeName}" ]]; then
        continue
    fi
    nodeCount+=1
    echo "Preparing worker node ${nodeName}..."

    declare dirArgs=""
    for d in "${requiredDirs[@]}"; do
        dirArgs="${dirArgs} ${d}"
    done

    if oc debug "node/${nodeName}" -- chroot /host mkdir -p ${dirArgs} 2>/dev/null; then
        echo "OK: created required directories on ${nodeName}"
    else
        echo "FAIL: could not create directories on ${nodeName}" >&2
        failures+=1
    fi
done < <(oc get nodes -l node-role.kubernetes.io/worker --no-headers \
    -o custom-columns=NAME:.metadata.name 2>/dev/null)

if [[ ${nodeCount} -eq 0 ]]; then
    echo "FAIL: no worker nodes found" >&2
    exit 1
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: could not prepare ${failures} worker node(s)" >&2
    exit 1
fi

echo "PASS: Worker nodes prepared (${nodeCount} nodes)"
exit 0
true
