#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

if [[ -z "${OPENSHIFT_UPGRADE_RELEASE_IMAGE_OVERRIDE:-}" ]]; then
    echo "SKIP: no upgrade target specified" >&2
    exit 2
fi

IFS=',' read -ra operators <<< "${OPP_OPERATORS:-advanced-cluster-management,rhacs-operator,odf-operator,quay-operator}"

declare -i timeoutMinutes=${UPGRADE_TIMEOUT:-130}
declare -i timeoutSeconds=$((timeoutMinutes * 60))
declare -i pollInterval=60

# Extract target version for matching
declare targetImage="${OPENSHIFT_UPGRADE_RELEASE_IMAGE_OVERRIDE}"

# ---- Start upgrade ----
echo "Starting OCP upgrade to image: ${targetImage}"
oc adm upgrade --to-image="${targetImage}" --allow-explicit-upgrade --force

# ---- Monitor upgrade ----
echo "Monitoring upgrade progress (timeout: ${timeoutMinutes} minutes)..."
declare -i elapsed=0
declare upgradeComplete="false"

while [[ ${elapsed} -lt ${timeoutSeconds} ]]; do
    declare upgradeStatus
    upgradeStatus=$(oc adm upgrade 2>/dev/null || true)

    # Check for completion: "Cluster version is <version>"
    if echo "${upgradeStatus}" | grep -q "Cluster version is"; then
        # Verify no upgrade is in progress
        if ! echo "${upgradeStatus}" | grep -qi "progressing"; then
            upgradeComplete="true"
            break
        fi
    fi

    declare -i elapsedMinutes=$((elapsed / 60))
    echo "  Upgrade in progress... (${elapsedMinutes}/${timeoutMinutes} min elapsed)"
    sleep ${pollInterval}
    elapsed=$((elapsed + pollInterval))
done

if [[ "${upgradeComplete}" != "true" ]]; then
    echo "FAIL: OCP upgrade did not complete within ${timeoutMinutes} minutes" >&2
    oc adm upgrade 2>/dev/null || true
    exit 1
fi

declare completedVersion
completedVersion=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
echo "Upgrade completed to version: ${completedVersion}"

# ---- Post-upgrade: check ClusterOperators ----
echo "Checking ClusterOperators post-upgrade..."
declare -i coFailures=0
while IFS= read -r line; do
    declare coName coAvailable coDegraded
    coName=$(echo "${line}" | awk '{print $1}')
    coAvailable=$(echo "${line}" | awk '{print $3}')
    coDegraded=$(echo "${line}" | awk '{print $5}')

    if [[ "${coAvailable}" != "True" ]]; then
        coFailures+=1
        echo "  ClusterOperator not Available: ${coName}" >&2
    fi
    if [[ "${coDegraded}" == "True" ]]; then
        coFailures+=1
        echo "  ClusterOperator Degraded: ${coName}" >&2
    fi
done < <(oc get clusteroperators --no-headers 2>/dev/null)

# ---- Post-upgrade: check Nodes ----
echo "Checking Nodes post-upgrade..."
declare -i nodeFailures=0
while IFS= read -r line; do
    declare nodeName nodeStatus
    nodeName=$(echo "${line}" | awk '{print $1}')
    nodeStatus=$(echo "${line}" | awk '{print $2}')
    if [[ "${nodeStatus}" != "Ready" ]]; then
        nodeFailures+=1
        echo "  Node not Ready: ${nodeName} (${nodeStatus})" >&2
    fi
done < <(oc get nodes --no-headers 2>/dev/null)

# ---- Post-upgrade: check OPP operator CSVs ----
echo "Checking OPP operator CSVs post-upgrade..."
declare -i csvFailures=0
for operator in "${operators[@]}"; do
    declare csvLine csvName csvNamespace csvPhase
    csvLine=$(oc get csv --all-namespaces --no-headers 2>/dev/null | grep "${operator}" | head -1 || true)
    if [[ -z "${csvLine}" ]]; then
        csvFailures+=1
        echo "  CSV not found for operator: ${operator}" >&2
        continue
    fi

    csvName=$(echo "${csvLine}" | awk '{print $2}')
    csvNamespace=$(echo "${csvLine}" | awk '{print $1}')
    csvPhase=$(oc get csv "${csvName}" -n "${csvNamespace}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

    if [[ "${csvPhase}" != "Succeeded" ]]; then
        csvFailures+=1
        echo "  CSV phase not Succeeded: ${operator} (${csvName} phase=${csvPhase})" >&2
    else
        echo "  OK: ${operator} (${csvName} phase=${csvPhase})"
    fi
done

declare -i totalFailures=$((coFailures + nodeFailures + csvFailures))
if [[ ${totalFailures} -gt 0 ]]; then
    echo "FAIL: post-upgrade validation found ${totalFailures} issue(s)" >&2
    exit 1
fi

echo "PASS: OCP upgrade completed and OPP operators healthy"
exit 0
true
