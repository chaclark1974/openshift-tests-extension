# stolostron-policy-collection

Shell-based OTE extension for ACM Policy Collection validation via the non-payload path. Tests verify governance framework prerequisites and validate policy YAML across NIST 800-53 control families.

## Prerequisites

- Go 1.23+
- `oc` CLI configured with `KUBECONFIG` pointing to a cluster with ACM installed
- `shellcheck` (optional, for linting)

## Build

```bash
make build
```

## Run Tests

```bash
# Run the full suite
make test

# Run NIST validation suite
./stolostron-policy-collection run-suite policy-collection/nist

# Run prerequisite checks only
./stolostron-policy-collection run-suite policy-collection/prerequisites

# Run with JUnit/HTML output (set ARTIFACT_DIR)
ARTIFACT_DIR=/tmp/artifacts make test
```

## Validate

```bash
make validate
```

## List Tests

```bash
./stolostron-policy-collection list tests
./stolostron-policy-collection list tests --suite policy-collection/smoke
./stolostron-policy-collection list suites
```

## Test Scripts

| Script | Description |
|--------|-------------|
| `check-acm-hub.sh` | Verify ACM hub is running |
| `check-governance-controller.sh` | Verify governance policy framework controller |
| `check-policy-crds.sh` | Verify Policy CRDs are installed |
| `check-policy-propagation.sh` | Verify policy propagation to managed clusters |
| `validate-ac-access-control.sh` | Validate AC (Access Control) policies |
| `validate-ca-security-assessment.sh` | Validate CA (Security Assessment) policies |
| `validate-cm-config-management.sh` | Validate CM (Configuration Management) policies |
| `validate-community-policies.sh` | Validate community-contributed policies |
| `validate-policygenerator-examples.sh` | Validate PolicyGenerator examples |
| `validate-sc-system-protection.sh` | Validate SC (System Protection) policies |
| `validate-si-system-integrity.sh` | Validate SI (System Integrity) policies |
| `validate-stable-policy-yamls.sh` | Validate stable policy YAML syntax |

## Suites

| Suite | Description |
|-------|-------------|
| `policy-collection/all` | All policy collection tests |
| `policy-collection/smoke` | Smoke tests only |
| `policy-collection/nist` | NIST 800-53 control family validation |
| `policy-collection/prerequisites` | ACM and governance prerequisites |

## Container Image

```bash
make image
# Override defaults:
IMAGE_REPO=quay.io/stolostron/policy-collection-tests IMAGE_TAG=v1.0 make image
```

## CI

```bash
make ci    # build + validate + lint-scripts
```
