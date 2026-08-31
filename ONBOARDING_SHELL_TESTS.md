# Automated Onboarding of Shell-Based Test Suites onto OTE (Non-Payload)

This guide provides a fully automated path to onboard shell-based test suites
into the OpenShift Tests Extension (OTE) framework **without using the payload
path**. A single scaffolding command generates the entire project — teams write
only shell scripts and a JSON manifest. No Go expertise required.

## Quick Start (5 Steps)

```bash
# 1. Generate project
./ote-scaffold.sh --name acme-tests --product acme --org github.com/acme-corp

# 2. Resolve Go dependencies
cd acme-tests && go mod tidy

# 3. Add your shell tests to scripts/, declare them in tests.json

# 4. Build and validate
make build && make validate

# 5. Run tests
./acme-tests run-suite acme/all
```

## How It Works

```
ote-scaffold.sh (run once)
        |
        v
your-tests/
├── cmd/your-tests/main.go    ← generated, imports pkg/shell from OTE
├── scripts/*.sh               ← your shell test scripts
├── tests.json                 ← your test manifest (the only file you edit)
├── Makefile                   ← generated
└── Dockerfile                 ← generated
```

The generated binary is a thin harness. It reads `tests.json` to discover
your tests, executes shell scripts, and translates exit codes into structured
OTE results. The shared library at `pkg/shell/` in this repository handles
all execution, manifest parsing, auto-discovery, and validation.

## Prerequisites

- Go 1.23+
- `bash`
- Access to `github.com/openshift-eng/openshift-tests-extension`

## Part 1: Scaffold a New Project

```bash
./ote-scaffold.sh \
  --name "acme-tests" \
  --product "acme" \
  --org "github.com/acme-corp" \
  --kind "external"
```

| Flag        | Description                                      | Default      |
|-------------|--------------------------------------------------|--------------|
| `--name`    | Binary and project directory name                | *(required)* |
| `--product` | Product identifier for OTE component             | *(required)* |
| `--org`     | Go module path prefix                            | *(required)* |
| `--kind`    | Component kind (see table below)                 | `external`   |

### Component Kind

The `kind` determines how the binary is classified — it does **not** affect
test execution.

| Kind               | Use Case                                          |
|--------------------|---------------------------------------------------|
| `"payload"`        | Ships in the OCP release payload (NOT this guide) |
| `"external"`       | Distributed outside the payload                   |
| `"layered-product"`| Tests for a layered product on top of OpenShift   |
| `"standalone"`     | Self-contained, run independently                 |

## Part 2: Shell Test Conventions

### Exit Codes

| Exit Code | OTE Result | Meaning                      |
|-----------|------------|------------------------------|
| `0`       | `passed`   | Test succeeded               |
| `2`       | `skipped`  | Test not applicable, skip it |
| Any other | `failed`   | Test failed                  |

### Output

All stdout/stderr is captured. Write diagnostics to help debug failures:

```bash
#!/bin/bash
echo "Checking API health at ${API_URL}..."
response=$(curl -sk -o /dev/null -w "%{http_code}" "${API_URL}/healthz")
if [[ "$response" == "200" ]]; then
    echo "PASS: API is healthy"
    exit 0
else
    echo "FAIL: Expected HTTP 200, got HTTP ${response}" >&2
    exit 1
fi
```

### Skipping on Missing Prerequisites

```bash
#!/bin/bash
if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping" >&2
    exit 2
fi
```

### Artifacts

Write large diagnostic artifacts to `$TEST_ARTIFACTS_DIR` (set by the runner
when `$EXTENSION_ARTIFACTS_DIR` is available):

```bash
if [[ -n "${TEST_ARTIFACTS_DIR:-}" ]]; then
    oc adm inspect clusteroperator \
        --dest-dir="${TEST_ARTIFACTS_DIR}/cluster-state" 2>/dev/null || true
fi
```

## Part 3: The Test Manifest (`tests.json`)

The manifest is the only file most teams edit. It declares tests, metadata,
and environment selectors in JSON.

### Schema

```json
{
  "$schema": "./tests.schema.json",
  "defaults": {
    "labels": [],
    "tags": { "product": "acme" },
    "lifecycle": "blocking",
    "timeout": "10m"
  },
  "tests": [
    {
      "name": "[sig-acme] descriptive test name",
      "script": "scripts/your-test.sh",
      "labels": ["SMOKE"],
      "tags": { "tier": "0" },
      "lifecycle": "blocking",
      "timeout": "5m",
      "include": "platform==\"aws\"",
      "exclude": "topology==\"single\""
    }
  ],
  "suites": [
    {
      "name": "acme/smoke",
      "description": "Smoke tests",
      "qualifiers": ["labels.exists(l, l==\"SMOKE\")"],
      "parents": ["openshift/conformance/parallel"]
    }
  ]
}
```

### Field Reference

| Field               | Scope    | Description                                                    |
|---------------------|----------|----------------------------------------------------------------|
| `defaults.labels`   | Global   | Labels applied to every test                                   |
| `defaults.tags`     | Global   | Tags applied to every test (per-test overrides on collision)   |
| `defaults.lifecycle`| Global   | `blocking` (fatal) or `informing` (logged only)               |
| `defaults.timeout`  | Global   | Default timeout as a Go duration (e.g., `10m`, `30s`)         |
| `tests[].name`      | Per-test | Full OTE test name. Convention: `[sig-xxx] description`        |
| `tests[].script`    | Per-test | Path to shell script, relative to the manifest                 |
| `tests[].labels`    | Per-test | Additional labels (merged with defaults)                       |
| `tests[].tags`      | Per-test | Additional tags (merged with defaults)                         |
| `tests[].lifecycle` | Per-test | Override the default lifecycle                                 |
| `tests[].timeout`   | Per-test | Override the default timeout                                   |
| `tests[].include`   | Per-test | CEL — test runs only when true                                |
| `tests[].exclude`   | Per-test | CEL — test skipped when true                                  |
| `suites[].name`     | Suite    | Suite name (e.g., `product/smoke`)                             |
| `suites[].qualifiers`| Suite   | CEL expressions OR'd for test selection                        |
| `suites[].parents`  | Suite    | Parent suites to participate in                                |

### Environment Selector CEL Expressions

| Expression                                      | Meaning                   |
|-------------------------------------------------|---------------------------|
| `platform=="aws"`                               | AWS only                  |
| `platform=="gcp" \|\| platform=="azure"`        | GCP or Azure              |
| `architecture=="amd64"`                         | x86_64 only               |
| `topology=="ha"`                                | HA topology               |
| `topology=="single"`                            | Single-node               |
| `network=="ovn"`                                | OVN networking            |
| `(platform=="aws") && (architecture=="amd64")`  | Combined                  |
| `featureGates.exists(fg, fg=="TechPreview")`    | Tech preview enabled      |
| `installer=="ipi"`                              | IPI-installed clusters    |

### Suite Qualifier CEL Expressions

| Expression                                         | Selects                       |
|----------------------------------------------------|-------------------------------|
| `labels.exists(l, l=="SMOKE")`                     | Tests with SMOKE label        |
| `!labels.exists(l, l=="SLOW")`                     | Tests without SLOW label      |
| `tags["tier"] == "0"`                              | Tier 0 tests                  |
| `name.contains("API")`                             | Tests with "API" in the name  |

## Part 4: Auto-Discovery Mode

If `tests.json` does not exist, the binary falls back to **auto-discovery**:
it scans `scripts/` for `.sh` files and registers one test per script.

```
scripts/
├── check-dns.sh       → [sig-acme] check dns
├── verify-api.sh      → [sig-acme] verify api
└── validate-certs.sh  → [sig-acme] validate certs
```

Good for getting started. Switch to a manifest when you need labels, tags,
environment selectors, or custom names.

## Part 5: Validation

Validate your manifest before building:

```bash
# The shared library validates at load time:
# - Required fields present
# - Scripts exist and are executable
# - Test names follow [sig-xxx] convention
# - No duplicate test names
# - Lifecycle values are valid
# - CEL expressions parse correctly
# - Timeouts are valid Go durations

# Quick validation:
make build && make validate
```

For editor autocompletion, add to the top of your `tests.json`:
```json
{ "$schema": "./tests.schema.json", ... }
```

Copy `tests.schema.json` from this repository into your project.

## Part 6: Build and Run

```bash
make build            # Build the binary
make validate         # Verify info, list tests, list suites
make test             # Run all tests
make list             # List test names
make lint-scripts     # Run shellcheck on scripts/

# Run specific commands
./your-tests run-test "[sig-acme] API health check"
./your-tests run-suite acme/smoke
./your-tests list tests --platform aws --architecture amd64
./your-tests list tests | jq '.[].name'
./your-tests info
```

## Part 7: Distribution

Since this binary is **not** in the release payload:

| Method           | How                                                            |
|------------------|----------------------------------------------------------------|
| Container image  | `make build && docker build -t registry/your-tests:latest .`   |
| Direct binary    | Host on an artifact server                                     |
| Source            | Teams clone and `make build`                                   |

The generated Dockerfile bundles binary, scripts, and manifest.

## Part 8: openshift-tests Integration

When `openshift-tests` orchestrates your binary:

```
openshift-tests                        your-tests
      |                                      |
      |── info ──────────────────────────────>|  metadata
      |<─────────────────────────────────────|
      |── list tests --platform aws ────────>|  filtered tests
      |<─────────────────────────────────────|
      |── run-test "test name" ──────────────>|  execute
      |<─────────────────────────────────────|  JSON result
      |  (repeat per test)                   |
```

## Part 9: OpenShift CI Step Registry Integration

The framework integrates with OpenShift CI step registry workflows. When
running inside CI (detected via `$OPENSHIFT_CI=true` or `$SHARED_DIR`), the
runner automatically bridges step registry environment variables.

### Automatic Environment Bridging

When CI is detected, the runner:

1. **Bridges `ARTIFACT_DIR`** — if `EXTENSION_ARTIFACTS_DIR` is not set,
   it uses CI's `$ARTIFACT_DIR` so artifacts are collected automatically.
2. **Isolates `SHARED_DIR`** — creates a per-test subdirectory under
   `$SHARED_DIR` so parallel tests don't collide. The original value is
   available as `$PARENT_SHARED_DIR`.
3. **Passes through all CI vars** — `KUBECONFIG`, `CLUSTER_PROFILE_DIR`,
   `LEASED_RESOURCE`, etc. are inherited from the parent process.

No code changes needed — this activates automatically in CI.

### Declaring Environment Variables in the Manifest

Use the `env` field to declare env vars your tests need:

```json
{
  "defaults": {
    "env": {
      "QUAY_URL": "https://quay.io"
    }
  },
  "tests": [
    {
      "name": "[sig-registry] API check",
      "script": "scripts/check-api.sh",
      "env": {
        "API_TIMEOUT": "30"
      }
    }
  ]
}
```

Manifest env vars have lowest precedence — they won't override values
already set in the environment (like CI-injected `KUBECONFIG`).

### Step Registry Metadata

For tests that need specific CI resources, declare them in the manifest:

```json
{
  "tests": [
    {
      "name": "[sig-acme] cluster test",
      "script": "scripts/cluster-test.sh",
      "from_image": "registry.ci.openshift.org/ocp/4.17:tests",
      "cluster_profile": "aws",
      "credentials": [
        {
          "namespace": "test-credentials",
          "name": "cloud-creds",
          "mount_path": "/var/run/cloud"
        }
      ]
    }
  ]
}
```

These fields are metadata used by the `generate-ci-refs` command — they
don't affect local test execution.

### Generating Step Registry Refs

Every extension binary includes a `generate-ci-refs` command:

```bash
./your-binary generate-ci-refs \
  --org-repo "openshift/your-tests" \
  --output-dir ci/step-registry
```

This generates per-suite ref files:

```
ci/step-registry/
├── your-tests-product-all-ref.yaml
├── your-tests-product-all-commands.sh
├── your-tests-product-smoke-ref.yaml
└── your-tests-product-smoke-commands.sh
```

Or include `--ci-org-repo` when scaffolding:

```bash
./ote-scaffold.sh --name acme-tests --product acme --org github.com/acme-corp \
  --ci-org-repo openshift/acme-tests
```

### Submitting to openshift/release

1. Generate refs: `./your-binary generate-ci-refs --org-repo org/repo`
2. Copy `ci/step-registry/` contents into `openshift/release` at
   `ci-operator/step-registry/org/repo/`
3. Reference the ref in your ci-operator config's workflow

## Shared Library Reference

The framework's shared library lives at `pkg/shell/` in this repository:

| File            | Purpose                                                   |
|-----------------|-----------------------------------------------------------|
| `runner.go`     | ShellTest type, BuildSpecs(), runShellTest() with timeout |
| `manifest.go`   | LoadManifest(), ParseManifest(), DiscoverScripts()        |
| `validate.go`   | ValidateManifest() for pre-build error checking           |

Downstream projects import these via:
```go
import "github.com/openshift-eng/openshift-tests-extension/pkg/shell"
```

## Reference Implementations

| Project                       | Tests | Suites | Description                              |
|-------------------------------|-------|--------|------------------------------------------|
| `quay-tests/`                 | 3     | 2      | Quay.io API validation                   |
| `cnv-tests/`                  | 3     | 2      | OpenShift Virtualization (CNV) smoke     |
| `virt-tests/`                 | 8     | 3      | KubeVirt infrastructure verification     |
| `opp-tests/`                  | 15    | 8      | OpenShift Platform Plus (mirrors interop-opp-aws) |
| `stolostron-policy-collection/`| 12   | 4      | ACM Policy Collection / NIST 800-53      |
| `pkg/cypress/`                | —     | —      | Cypress integration (different runner)   |

## Part 10: CI Templates

The `ci/` directory provides reusable templates for wiring OTE shell test projects into CI.

### Makefile Include (`ci/ote-shell.mk`)

Add standard OTE targets to your Makefile with four variables:

```makefile
OTE_BINARY   := cnv-tests
OTE_PRODUCT  := cnv
OTE_CMD_PATH := ./cmd/cnv-tests/...
OTE_ORG_REPO := openshift/cnv-tests
include ../ci/ote-shell.mk
```

Targets provided:
- `ote-build` — Build the OTE binary
- `ote-test` — Run the default suite (with JUnit/HTML when `ARTIFACT_DIR` is set)
- `ote-validate` — Run `info`, `list tests`, `list suites`
- `ote-lint` — Run shellcheck on `scripts/`
- `ote-ci` — Full pipeline: build, validate, lint, test
- `ote-generate-refs` — Generate step registry ref files

### ci-operator Config (`ci/ci-operator-template.yaml`)

Template for `openshift/release` CI config. Replace placeholders (`ORG_NAME`, `REPO_NAME`, `PRODUCT_NAME`, `BINARY_NAME`, `BRANCH`) and place in:

```
openshift/release/ci-operator/config/ORG_NAME/REPO_NAME/ORG_NAME-REPO_NAME-BRANCH.yaml
```

### Prow Periodic Job (`ci/prow-job-template.yaml`)

Template for Prow periodic jobs. Replace placeholders and place in:

```
openshift/release/ci-operator/jobs/ORG_NAME/REPO_NAME/
```

## Onboarding Checklist

- [ ] Ran `ote-scaffold.sh` with correct `--name`, `--product`, `--org`
- [ ] `go mod tidy` succeeds
- [ ] Shell scripts exit 0 (pass), 2 (skip), or non-zero (fail)
- [ ] Scripts are executable (`chmod +x scripts/*.sh`)
- [ ] `tests.json` entries have `[sig-xxx]` prefixed names
- [ ] No duplicate test names
- [ ] `make build && make validate` passes
- [ ] `make test` runs and reports correct results
- [ ] Environment selectors set for platform-specific tests
- [ ] Suite parents declared if participating in `openshift-tests` suites
- [ ] `lifecycle` set to `informing` for tests still stabilizing
- [ ] `shellcheck scripts/*.sh` passes
- [ ] CI env vars documented in `tests.json` `env` field (if applicable)
- [ ] `generate-ci-refs` produces valid step registry refs (if using CI)
- [ ] Container image builds with `make image`
- [ ] README.md is present and accurate

## Part 11: Interactive Onboarding (`ote-onboard`)

For a guided experience, use the interactive CLI:

```bash
make ote-onboard
./ote-onboard
```

It prompts for project name, product, org, kind, and CI org/repo, then:
1. Runs `ote-scaffold.sh` with your answers
2. Runs `go mod tidy`
3. Runs `make build && make validate`

The result is a fully functional, validated project ready for test scripts.

## Part 12: Suite Configuration in Manifest

Suites can specify parallelism and per-suite test timeouts:

```json
{
  "suites": [
    {
      "name": "acme/all",
      "description": "All tests",
      "parallelism": 4,
      "testTimeout": "15m"
    },
    {
      "name": "acme/smoke",
      "description": "Fast smoke tests",
      "qualifiers": ["labels.exists(l, l==\"SMOKE\")"],
      "parallelism": 8,
      "testTimeout": "2m"
    }
  ]
}
```

| Field          | Type   | Description                                  |
|----------------|--------|----------------------------------------------|
| `parallelism`  | int    | Max concurrent tests in this suite           |
| `testTimeout`  | string | Go duration override for tests in this suite |

## Part 13: JUnit and HTML Reports

When `ARTIFACT_DIR` is set, the generated Makefile `test` target automatically
produces JUnit XML and HTML reports:

```bash
ARTIFACT_DIR=/tmp/artifacts make test
# Creates:
#   /tmp/artifacts/junit_<product>_<timestamp>.xml
#   /tmp/artifacts/results-<product>-<timestamp>.html
```

You can also pass `--junit-path` and `--html-path` directly:

```bash
./your-tests run-suite product/all \
    --junit-path results.xml \
    --html-path results.html
```

## Part 14: Container Images

Each product includes a multi-stage UBI9 Dockerfile:

```bash
make image                              # Uses default quay.io/openshift/<name>:latest
IMAGE_REPO=myregistry.io/foo IMAGE_TAG=v1.0 make image   # Override registry/tag
```

The Dockerfile uses repo-root build context to resolve the `replace ../`
directive in `go.mod`. When running `podman build` manually:

```bash
podman build -t myimage:latest -f Dockerfile ..
```

## Onboarding Cookbook

### Recipe: Add a new test

1. Write a shell script in `scripts/`:
```bash
#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "KUBECONFIG not set, skipping"
    exit 2
fi

oc get nodes
echo "PASS: cluster is reachable"
exit 0
true
```

2. Add an entry to `tests.json`:
```json
{
  "name": "[sig-product] cluster is reachable",
  "script": "scripts/check-cluster.sh",
  "labels": ["SMOKE"],
  "tags": { "tier": "0" }
}
```

3. `chmod +x scripts/check-cluster.sh && make build && make validate`

### Recipe: Add a suite

Add to the `suites` array in `tests.json`:

```json
{
  "name": "product/nightly",
  "description": "Long-running nightly tests",
  "qualifiers": ["tags[\"tier\"] == \"1\""],
  "parallelism": 2,
  "testTimeout": "30m"
}
```

### Recipe: Skip on missing prerequisites

```bash
if ! command -v oc &>/dev/null; then
    echo "oc CLI not found, skipping"
    exit 2
fi

if ! oc whoami &>/dev/null; then
    echo "Not logged in to cluster, skipping"
    exit 2
fi
```

### Recipe: Platform-specific tests

In `tests.json`, use the `include`/`exclude` CEL fields:

```json
{
  "name": "[sig-product] AWS-specific storage check",
  "script": "scripts/check-ebs.sh",
  "include": "platform==\"aws\""
}
```

This test will only run when `--platform aws` is passed.

### Recipe: Collect artifacts

```bash
if [[ -n "${TEST_ARTIFACTS_DIR:-}" ]]; then
    oc adm inspect clusteroperator \
        --dest-dir="${TEST_ARTIFACTS_DIR}/inspect" 2>/dev/null || true
    oc get events -A > "${TEST_ARTIFACTS_DIR}/events.txt" 2>/dev/null || true
fi
```

### Recipe: Environment variables from manifest

```json
{
  "defaults": {
    "env": {
      "MY_NAMESPACE": "my-product"
    }
  }
}
```

Scripts can use `$MY_NAMESPACE` directly. CI-injected values (`KUBECONFIG`,
`ARTIFACT_DIR`) always take precedence over manifest defaults.

## FAQ

**Q: Do I need to know Go?**
No. Run `ote-scaffold.sh` (or `ote-onboard`) once, then only edit shell
scripts and `tests.json`. The generated Go code never needs modification.

**Q: Can tests run in parallel?**
Yes. Set `"parallelism": N` on a suite in `tests.json`. The framework
manages concurrency.

**Q: How do I mark a flaky test as non-blocking?**
Set `"lifecycle": "informing"` on the test in `tests.json`. It will still
run and report, but failures won't block CI.

**Q: What if my test needs to run on specific platforms only?**
Use the `include` field with a CEL expression:
`"include": "platform==\"aws\""`. The orchestrator filters before execution.

**Q: How do I debug a failing test locally?**
Run it directly: `./your-tests run-test "[sig-product] my test name"`.
The full stdout/stderr is captured in the JSON result's `output` field.
