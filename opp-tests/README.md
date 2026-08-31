# opp-tests

Shell-based OTE extension for OpenShift Platform Plus (OPP) component verification via the non-payload path. Test coverage mirrors the `interop-opp-aws` CI environment.

## Prerequisites

- Go 1.23+
- `oc` CLI configured with `KUBECONFIG` pointing to a cluster with OPP components installed (ACM, ACS, ODF, Quay, Compliance Operator)
- `shellcheck` (optional, for linting)

## Build

```bash
make build
```

## Run Tests

```bash
# Run the full suite
make test

# Run a component-specific suite
./opp-tests run-suite opp/acs
./opp-tests run-suite opp/acm
./opp-tests run-suite opp/odf
./opp-tests run-suite opp/quay

# Run with JUnit/HTML output (set ARTIFACT_DIR)
ARTIFACT_DIR=/tmp/artifacts make test
```

## Validate

```bash
make validate
```

## List Tests

```bash
./opp-tests list tests
./opp-tests list tests --suite opp/smoke
./opp-tests list suites
```

## Test Scripts

| Script | Component | Description |
|--------|-----------|-------------|
| `check-cluster-health.sh` | preflight | Verify cluster nodes and operators healthy |
| `check-opp-operators-csv.sh` | preflight | Verify all OPP operator CSVs succeeded |
| `check-acm-hub.sh` | acm | Verify ACM hub is running |
| `check-acm-managed-clusters.sh` | acm | Verify managed clusters are available |
| `check-acm-policies-compliant.sh` | acm | Verify ACM policies are compliant |
| `check-acm-observability.sh` | acm | Verify ACM observability stack |
| `check-acs-central.sh` | acs | Verify ACS Central deployment |
| `check-acs-scanner.sh` | acs | Verify ACS Scanner deployment |
| `check-acs-secured-clusters.sh` | acs | Verify ACS SecuredCluster resources |
| `check-acs-init-bundle.sh` | acs | Verify ACS init bundle applied |
| `check-odf-deployment.sh` | odf | Verify ODF StorageCluster is ready |
| `check-odf-noobaa.sh` | odf | Verify NooBaa system is ready |
| `check-compliance-operator.sh` | compliance | Verify Compliance Operator is running |
| `check-quay-registry.sh` | quay | Verify Quay registry is available |
| `check-quay-bridge.sh` | quay | Verify Quay bridge operator |

## Suites

| Suite | Description |
|-------|-------------|
| `opp/all` | All OPP tests |
| `opp/smoke` | Smoke tests only |
| `opp/preflight` | Cluster health and operator prerequisite checks |
| `opp/install` | Installation verification tests |
| `opp/acs` | ACS component tests |
| `opp/acm` | ACM component tests |
| `opp/odf` | ODF component tests |
| `opp/quay` | Quay component tests |

## Container Image

```bash
make image
# Override defaults:
IMAGE_REPO=myregistry.io/opp-tests IMAGE_TAG=v1.0 make image
```

## CI

```bash
make ci    # build + validate + lint-scripts
```
