#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "SKIP: KUBECONFIG not set" >&2
    exit 2
fi

declare namespace="ibm-fusion-access"

# Check namespace exists
if ! oc get namespace "${namespace}" &>/dev/null; then
    echo "FAIL: namespace ${namespace} does not exist -- create namespaces first" >&2
    exit 1
fi

# Create CatalogSource for IBM operator catalog
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: IBM Operator Catalog
  publisher: IBM
  sourceType: grpc
  image: icr.io/cpopen/ibm-operator-catalog:latest
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
echo "Created CatalogSource ibm-operator-catalog"

# Wait for CatalogSource to be READY
declare -i csTimeout=300
declare -i elapsed=0
declare csState=""
echo "Waiting for CatalogSource ibm-operator-catalog to be READY (timeout ${csTimeout}s)..."
while [[ ${elapsed} -lt ${csTimeout} ]]; do
    csState=$(oc get catalogsource ibm-operator-catalog -n openshift-marketplace \
        -o jsonpath='{.status.connectionState.lastObservedState}' 2>/dev/null) || true
    if [[ "${csState}" == "READY" ]]; then
        echo "CatalogSource ibm-operator-catalog is READY"
        break
    fi
    sleep 10
    elapsed+=10
done

if [[ "${csState}" != "READY" ]]; then
    echo "FAIL: CatalogSource ibm-operator-catalog did not reach READY state within ${csTimeout}s (state: ${csState:-NotFound})" >&2
    exit 1
fi

# Create OperatorGroup if one does not already exist
if ! oc get operatorgroup -n "${namespace}" --no-headers 2>/dev/null | grep -q .; then
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-fusion-access-operatorgroup
  namespace: ${namespace}
spec:
  targetNamespaces:
  - ${namespace}
EOF
    echo "Created OperatorGroup in ${namespace}"
else
    echo "OperatorGroup already exists in ${namespace}"
fi

# Create Subscription for ibm-fusion-access-operator
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-fusion-access-operator
  namespace: ${namespace}
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: ibm-fusion-access-operator
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF
echo "Created Subscription for ibm-fusion-access-operator on alpha channel"

# Wait for CSV to succeed (poll up to 60 times, 10s apart = 600s)
declare -i maxPolls=60
declare -i poll=0
declare csvPhase=""
echo "Waiting for ibm-fusion-access-operator CSV to reach Succeeded phase (up to ${maxPolls} polls)..."
while [[ ${poll} -lt ${maxPolls} ]]; do
    declare csvName
    csvName=$(oc get csv -n "${namespace}" --no-headers 2>/dev/null \
        | grep "ibm-fusion-access" | head -1 | awk '{print $1}') || true
    if [[ -n "${csvName}" ]]; then
        csvPhase=$(oc get csv "${csvName}" -n "${namespace}" \
            -o jsonpath='{.status.phase}' 2>/dev/null) || true
        if [[ "${csvPhase}" == "Succeeded" ]]; then
            echo "CSV ${csvName} is Succeeded"
            break
        fi
        echo "Poll ${poll}/${maxPolls}: CSV ${csvName} phase=${csvPhase:-Pending}"
    else
        echo "Poll ${poll}/${maxPolls}: CSV not yet created"
    fi
    sleep 10
    poll+=1
done

if [[ "${csvPhase}" != "Succeeded" ]]; then
    echo "FAIL: ibm-fusion-access-operator CSV did not reach Succeeded phase after ${maxPolls} polls (phase: ${csvPhase:-NotFound})" >&2
    if [[ -n "${ARTIFACT_DIR:-}" ]]; then
        oc get csv -n "${namespace}" -o yaml > "${ARTIFACT_DIR}/ibm-fa-csv.yaml" 2>/dev/null || true
    fi
    exit 1
fi

echo "PASS: Fusion Access operator installed"
exit 0
true
