#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

IFS=',' read -ra operators <<< "${OPP_OPERATORS:-advanced-cluster-management,rhacs-operator,odf-operator,quay-operator}"

# Validate that at least one OPP operator CSV exists
declare -i operatorCount=0
for operator in "${operators[@]}"; do
    declare csvLine
    csvLine=$(oc get csv --all-namespaces --no-headers 2>/dev/null | grep "${operator}" | head -1 || true)
    if [[ -n "${csvLine}" ]]; then
        operatorCount+=1
        echo "  Found operator CSV: ${operator}"
    else
        echo "  WARN: no CSV found for ${operator}" >&2
    fi
done

if [[ ${operatorCount} -eq 0 ]]; then
    echo "FAIL: no OPP operator CSVs found on the cluster" >&2
    exit 1
fi

if [[ -n "${ARTIFACT_DIR:-}" ]]; then
    declare backupDir="${ARTIFACT_DIR}/backup"
    mkdir -p "${backupDir}"

    echo "Capturing ClusterVersion..."
    oc get clusterversion -o yaml > "${backupDir}/clusterversion.yaml" 2>/dev/null || true

    echo "Capturing ClusterOperators..."
    oc get clusteroperators -o yaml > "${backupDir}/clusteroperators.yaml" 2>/dev/null || true

    echo "Capturing Nodes..."
    oc get nodes -o yaml > "${backupDir}/nodes.yaml" 2>/dev/null || true

    echo "Capturing CSVs..."
    oc get csv --all-namespaces -o yaml > "${backupDir}/csvs.yaml" 2>/dev/null || true

    # Capture individual OPP operator CSV status
    for operator in "${operators[@]}"; do
        declare csvName csvNamespace csvPhase
        csvName=$(oc get csv --all-namespaces --no-headers 2>/dev/null | grep "${operator}" | head -1 | awk '{print $2}' || true)
        csvNamespace=$(oc get csv --all-namespaces --no-headers 2>/dev/null | grep "${operator}" | head -1 | awk '{print $1}' || true)
        csvPhase=""
        if [[ -n "${csvName}" && -n "${csvNamespace}" ]]; then
            csvPhase=$(oc get csv "${csvName}" -n "${csvNamespace}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            oc get csv "${csvName}" -n "${csvNamespace}" -o yaml > "${backupDir}/csv-${operator}.yaml" 2>/dev/null || true
        fi
    done

    # Create backup manifest summary
    declare clusterVersion
    clusterVersion=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
    declare timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "${backupDir}/backup-manifest.json" <<MANIFEST
{
  "timestamp": "${timestamp}",
  "clusterVersion": "${clusterVersion}",
  "operators": [$(
    declare -i idx=0
    for operator in "${operators[@]}"; do
        declare mCsvName mCsvPhase
        mCsvName=$(oc get csv --all-namespaces --no-headers 2>/dev/null | grep "${operator}" | head -1 | awk '{print $2}' || true)
        mCsvPhase=""
        if [[ -n "${mCsvName}" ]]; then
            declare mCsvNs
            mCsvNs=$(oc get csv --all-namespaces --no-headers 2>/dev/null | grep "${operator}" | head -1 | awk '{print $1}' || true)
            mCsvPhase=$(oc get csv "${mCsvName}" -n "${mCsvNs}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        fi
        if [[ ${idx} -gt 0 ]]; then echo -n ","; fi
        echo -n "
    {\"name\": \"${operator}\", \"csv\": \"${mCsvName:-none}\", \"phase\": \"${mCsvPhase:-NotFound}\"}"
        idx+=1
    done
)
  ],
  "artifacts": "$(ls "${backupDir}" | tr '\n' ',' | sed 's/,$//')"
}
MANIFEST
    echo "  Backup manifest written to ${backupDir}/backup-manifest.json"
else
    echo "  ARTIFACT_DIR not set, skipping file writes"
fi

echo "PASS: Pre-upgrade backup captured"
exit 0
true
