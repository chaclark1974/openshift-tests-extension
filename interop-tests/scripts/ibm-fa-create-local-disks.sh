#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare namespace="ibm-spectrum-scale"

# Check that ibm-spectrum-scale namespace exists
if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "FAIL: namespace ${namespace} does not exist -- create namespaces first" >&2
    exit 1
fi

# Device list for EBS-backed NVMe volumes
declare -a devices=("nvme2n1" "nvme3n1" "nvme4n1")
declare -i failures=0

for dev in "${devices[@]}"; do
    declare diskName="localdisk-${dev}"
    cat <<EOF | oc apply -f -
apiVersion: scale.spectrum.ibm.com/v1beta1
kind: LocalDisk
metadata:
  name: ${diskName}
  namespace: ${namespace}
spec:
  devicePath: /dev/${dev}
EOF
    if [[ $? -ne 0 ]]; then
        echo "FAIL: could not create LocalDisk ${diskName}" >&2
        failures+=1
    else
        echo "OK: LocalDisk ${diskName} created for /dev/${dev}"
    fi
done

# Verify LocalDisk CRs exist
for dev in "${devices[@]}"; do
    declare diskName="localdisk-${dev}"
    if ! oc get localdisk "${diskName}" -n "${namespace}" &>/dev/null; then
        echo "FAIL: LocalDisk ${diskName} not found after creation" >&2
        failures+=1
    fi
done

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: ${failures} LocalDisk resource(s) could not be created or verified" >&2
    exit 1
fi

echo "PASS: LocalDisk resources created"
exit 0
true
