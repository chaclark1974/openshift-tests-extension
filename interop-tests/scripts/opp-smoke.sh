#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

IFS=',' read -ra operators <<< "${OPP_OPERATORS:-advanced-cluster-management,rhacs-operator,odf-operator,quay-operator}"

declare -i failures=0

# ---- Check cluster health: ClusterOperators ----
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

# ---- Check OPP operator CSVs and pods ----
echo "Checking OPP operator CSVs and pods..."
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
        echo "  OK: ${operator} CSV (${csvName} phase=${csvPhase})"
    fi

    # Check pods in operator namespace are Running
    declare -i podFailures=0
    while IFS= read -r podLine; do
        [[ -z "${podLine}" ]] && continue
        declare podName podStatus
        podName=$(echo "${podLine}" | awk '{print $1}')
        podStatus=$(echo "${podLine}" | awk '{print $3}')
        if [[ "${podStatus}" != "Running" && "${podStatus}" != "Completed" && "${podStatus}" != "Succeeded" ]]; then
            podFailures+=1
            echo "  Pod not healthy in ${csvNamespace}: ${podName} (${podStatus})" >&2
        fi
    done < <(oc get pods -n "${csvNamespace}" --no-headers 2>/dev/null)

    if [[ ${podFailures} -gt 0 ]]; then
        failures+=1
        echo "  ${podFailures} unhealthy pod(s) in namespace ${csvNamespace}" >&2
    fi
done

# ---- ACM-specific: check ManagedCluster resources ----
if echo "${operators[@]}" | grep -q "advanced-cluster-management"; then
    echo "Checking ACM ManagedCluster resources..."
    declare acmInstalled
    acmInstalled=$(oc get csv --all-namespaces --no-headers 2>/dev/null | grep "advanced-cluster-management" | head -1 || true)
    if [[ -n "${acmInstalled}" ]]; then
        declare mcCount
        mcCount=$(oc get managedclusters --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [[ "${mcCount}" -gt 0 ]]; then
            while IFS= read -r mcLine; do
                declare mcName mcJoined mcAvailable
                mcName=$(echo "${mcLine}" | awk '{print $1}')
                mcJoined=$(echo "${mcLine}" | awk '{print $2}')
                mcAvailable=$(echo "${mcLine}" | awk '{print $3}')
                if [[ "${mcAvailable}" != "True" ]]; then
                    failures+=1
                    echo "  ManagedCluster not Available: ${mcName} (joined=${mcJoined}, available=${mcAvailable})" >&2
                fi
            done < <(oc get managedclusters --no-headers 2>/dev/null)
            echo "  OK: ${mcCount} ManagedCluster(s) found"
        else
            echo "  WARN: no ManagedClusters found (may not apply)" >&2
        fi
    fi
fi

# ---- ACS-specific: check SecuredCluster CR ----
if echo "${operators[@]}" | grep -q "rhacs-operator"; then
    echo "Checking ACS SecuredCluster CR..."
    declare acsInstalled
    acsInstalled=$(oc get csv --all-namespaces --no-headers 2>/dev/null | grep "rhacs-operator" | head -1 || true)
    if [[ -n "${acsInstalled}" ]]; then
        declare acsNamespace="${ACS_NAMESPACE:-stackrox}"
        if ! oc get namespace "${acsNamespace}" &>/dev/null; then
            declare altNs="rhacs-operator"
            if oc get namespace "${altNs}" &>/dev/null; then
                acsNamespace="${altNs}"
            fi
        fi

        declare scStatus
        scStatus=$(oc get securedcluster -n "${acsNamespace}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -z "${scStatus}" ]]; then
            echo "  WARN: no SecuredCluster CR found in ${acsNamespace}" >&2
        else
            echo "  OK: SecuredCluster CR exists: ${scStatus}"
        fi
    fi
fi

if [[ ${failures} -gt 0 ]]; then
    echo "FAIL: post-upgrade smoke tests found ${failures} issue(s)" >&2
    exit 1
fi

echo "PASS: OPP post-upgrade smoke tests passed"
exit 0
true
