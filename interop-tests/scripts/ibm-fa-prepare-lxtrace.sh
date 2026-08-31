#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

# Workaround for IBM Storage Scale v5.2.3.1 on RHCOS:
# The lxtrace utility is not available on RHCOS, but Storage Scale checks
# for it during startup. Creating dummy files prevents the check from failing.

declare -a lxtraceFiles=(
    "/usr/bin/lxtrace"
    "/usr/bin/lxtrace.bin"
)

declare -i failures=0
declare -i nodeCount=0

while IFS= read -r nodeName; do
    if [[ -z "${nodeName}" ]]; then
        continue
    fi
    nodeCount+=1
    echo "Creating lxtrace dummy files on ${nodeName}..."

    declare script=""
    for f in "${lxtraceFiles[@]}"; do
        script="${script}touch ${f} && chmod 755 ${f} && "
    done
    script="${script}true"

    if oc debug "node/${nodeName}" -- chroot /host bash -c "${script}" 2>/dev/null; then
        echo "OK: lxtrace dummy files created on ${nodeName}"
    else
        echo "FAIL: could not create lxtrace files on ${nodeName}" >&2
        failures+=1
    fi
done < <(oc get nodes -l node-role.kubernetes.io/worker --no-headers \
    -o custom-columns=NAME:.metadata.name 2>/dev/null)

if [[ ${nodeCount} -eq 0 ]]; then
    echo "FAIL: no worker nodes found" >&2
    exit 1
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: could not create lxtrace files on ${failures} worker node(s)" >&2
    exit 1
fi

echo "PASS: lxtrace files created (${nodeCount} nodes)"
exit 0
true
