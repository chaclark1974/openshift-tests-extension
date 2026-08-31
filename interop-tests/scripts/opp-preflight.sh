#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

IFS=',' read -ra operators <<< "${OPP_OPERATORS:-advanced-cluster-management,rhacs-operator,odf-operator,quay-operator}"

declare -i failures=0

# ---- Check ClusterOperators ----
echo "Checking ClusterOperators..."
while IFS= read -r line; do
    declare coName coAvailable coDegraded
    coName=$(echo "${line}" | awk '{print $1}')
    coAvailable=$(echo "${line}" | awk '{print $3}')
    coDegraded=$(echo "${line}" | awk '{print $5}')

    if [[ "${coAvailable}" != "True" ]]; then
        failures+=1
        echo "  ClusterOperator not Available: ${coName}" >&2
    fi
    if [[ "${coDegraded}" == "True" ]]; then
        failures+=1
        echo "  ClusterOperator Degraded: ${coName}" >&2
    fi
done < <(oc get clusteroperators --no-headers 2>/dev/null)

# ---- Check Nodes ----
echo "Checking Nodes..."
while IFS= read -r line; do
    declare nodeName nodeStatus
    nodeName=$(echo "${line}" | awk '{print $1}')
    nodeStatus=$(echo "${line}" | awk '{print $2}')
    if [[ "${nodeStatus}" != "Ready" ]]; then
        failures+=1
        echo "  Node not Ready: ${nodeName} (${nodeStatus})" >&2
    fi
done < <(oc get nodes --no-headers 2>/dev/null)

# ---- Check MachineConfigPools ----
echo "Checking MachineConfigPools..."
while IFS= read -r line; do
    declare mcpName mcpUpdated mcpUpdating mcpDegraded
    mcpName=$(echo "${line}" | awk '{print $1}')
    mcpUpdated=$(echo "${line}" | awk '{print $3}')
    mcpUpdating=$(echo "${line}" | awk '{print $4}')
    mcpDegraded=$(echo "${line}" | awk '{print $5}')

    if [[ "${mcpUpdated}" != "True" ]]; then
        failures+=1
        echo "  MachineConfigPool not Updated: ${mcpName}" >&2
    fi
    if [[ "${mcpUpdating}" == "True" ]]; then
        failures+=1
        echo "  MachineConfigPool still Updating: ${mcpName}" >&2
    fi
    if [[ "${mcpDegraded}" == "True" ]]; then
        failures+=1
        echo "  MachineConfigPool Degraded: ${mcpName}" >&2
    fi
done < <(oc get machineconfigpools --no-headers 2>/dev/null)

# ---- Check OPP operator CSVs ----
echo "Checking OPP operator CSVs..."
for operator in "${operators[@]}"; do
    declare csvLine csvName csvNamespace csvPhase
    csvLine=$(oc get csv --all-namespaces --no-headers 2>/dev/null | grep "${operator}" | head -1 || true)
    if [[ -z "${csvLine}" ]]; then
        failures+=1
        echo "  CSV not found for operator: ${operator}" >&2
        continue
    fi

    csvName=$(echo "${csvLine}" | awk '{print $2}')
    csvNamespace=$(echo "${csvLine}" | awk '{print $1}')
    csvPhase=$(oc get csv "${csvName}" -n "${csvNamespace}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

    if [[ "${csvPhase}" != "Succeeded" ]]; then
        failures+=1
        echo "  CSV phase not Succeeded: ${operator} (${csvName} phase=${csvPhase})" >&2
    else
        echo "  OK: ${operator} (${csvName} phase=${csvPhase})"
    fi
done

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: pre-flight validation found ${failures} issue(s)" >&2
    exit 1
fi

echo "PASS: pre-flight validation passed"
exit 0
true
