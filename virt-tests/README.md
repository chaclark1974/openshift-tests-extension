# virt-tests

Shell-based OTE extension for KubeVirt infrastructure verification via the non-payload path.

## Prerequisites

- Go 1.23+
- `oc` CLI configured with `KUBECONFIG` pointing to a cluster with KubeVirt/CNV installed
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
./virt-tests list tests
./virt-tests list tests --suite virt/smoke
./virt-tests list suites
```

## Test Scripts

| Script | Description |
|--------|-------------|
| `check-kubevirt-deployment.sh` | Verify KubeVirt operator deployment |
| `check-virt-handler.sh` | Verify virt-handler DaemonSet |
| `check-virt-controller.sh` | Verify virt-controller deployment |
| `check-vm-crds.sh` | Verify VM-related CRDs exist |
| `check-cdi-deployment.sh` | Verify CDI operator deployment |
| `check-live-migration-ready.sh` | Verify live migration is enabled |
| `check-storage-profiles.sh` | Verify StorageProfile resources |
| `check-network-addons.sh` | Verify network addons operator |

## Suites

| Suite | Description |
|-------|-------------|
| `virt/all` | All virtualization tests |
| `virt/smoke` | Smoke tests only |
| `virt/infrastructure` | Infrastructure component checks |

## Container Image

```bash
make image
# Override defaults:
IMAGE_REPO=myregistry.io/virt-tests IMAGE_TAG=v1.0 make image
```

## CI

```bash
make ci    # build + validate + lint-scripts
```
