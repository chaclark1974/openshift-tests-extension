# cnv-tests

Shell-based OTE extension for OpenShift Virtualization (CNV) smoke testing via the non-payload path.

## Prerequisites

- Go 1.23+
- `oc` CLI configured with `KUBECONFIG` pointing to a cluster with CNV installed
- `shellcheck` (optional, for linting)

## Build

```bash
make build
```

## Run Tests

```bash
# Run the full suite
make test

# Run with JUnit/HTML output (set ARTIFACT_DIR)
ARTIFACT_DIR=/tmp/artifacts make test
```

## Validate

```bash
make validate
```

## List Tests

```bash
./cnv-tests list tests
./cnv-tests list tests --suite cnv/smoke
./cnv-tests list suites
```

## Test Scripts

| Script | Description |
|--------|-------------|
| `check-cnv-operator.sh` | Verify HyperConverged operator is running |
| `check-virt-api.sh` | Verify virt-api deployment is available |
| `check-vm-crd.sh` | Verify VirtualMachine CRD exists |

## Suites

| Suite | Description |
|-------|-------------|
| `cnv/all` | All CNV tests |
| `cnv/smoke` | Smoke tests only |

## Container Image

```bash
make image
# Override defaults:
IMAGE_REPO=myregistry.io/cnv-tests IMAGE_TAG=v1.0 make image
```

## CI

```bash
make ci    # build + validate + lint-scripts
```
