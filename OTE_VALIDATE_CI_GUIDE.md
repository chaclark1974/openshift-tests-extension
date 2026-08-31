# ote-validate-ci User Guide

`ote-validate-ci` validates that OTE (OpenShift Tests Extension) product tests,
suites, and CI step-registry refs are internally consistent and optionally
aligned with upstream CI step-registry refs.

## Building

```bash
make ote-validate-ci
```

This produces the `ote-validate-ci` binary in the repository root.

## Quick Start

```bash
# Validate a single component (local checks only)
./ote-validate-ci --component cnv

# Validate all components
./ote-validate-ci --all

# Validate against upstream CI refs in openshift/release
./ote-validate-ci --component cnv --ci-repo openshift/release

# Validate against a local clone of openshift/release
./ote-validate-ci --component cnv --ci-path /path/to/openshift/release/ci-operator/step-registry
```

## Flags

| Flag | Required | Description |
|------|----------|-------------|
| `--component` | Yes* | Component to validate: `cnv`, `virt`, `opp`, `policy-collection` |
| `--all` | Yes* | Validate all known components |
| `--ci-path` | No | Local path to a CI step-registry directory (e.g., from a cloned `openshift/release`) |
| `--ci-repo` | No | GitHub repo for upstream ref comparison via `gh api` |

*One of `--component` or `--all` is required.

`--ci-repo` accepts any of these formats:
- `openshift/release`
- `https://github.com/openshift/release`
- `https://github.com/openshift/release.git`

## Components

Each component maps to a product directory, binary, and upstream CI path:

| Component | Directory | Binary | Upstream CI Path |
|-----------|-----------|--------|------------------|
| `cnv` | `cnv-tests/` | `cnv-tests` | `cnv/` |
| `virt` | `virt-tests/` | `virt-tests` | `kubevirt/` |
| `opp` | `opp-tests/` | `opp-tests` | `acm/` |
| `policy-collection` | `stolostron-policy-collection/` | `stolostron-policy-collection` | `acm/` |

## Validation Phases

### Phase 1: OTE Internal Checks (always runs)

These checks run against the local product directory with no network access
required.

**1. Test scripts exist and are executable**

Every test entry in `tests.json` must have a script file that exists on disk and
has executable permissions.

```
[PASS] All 3 test scripts exist and are executable
[FAIL] Test script missing: scripts/smoke.sh (cnv-operator-smoke)
[FAIL] Test script not executable: scripts/deploy.sh
```

**2. Local CI refs match suites**

Every suite in `tests.json` must have a corresponding `*-ref.yaml` file in
`<product>/ci/step-registry/`. The expected ref name is derived using
`stepregistry.MakeRefName(orgRepo, suiteName)`, which produces names like
`cnv-tests-cnv-smoke`.

```
[PASS] Suite cnv/all -> local ref cnv-tests-cnv-all
[FAIL] Suite cnv/smoke has no local CI ref (expected: cnv-tests-cnv-smoke)
```

To generate missing refs, run:

```bash
cd <product-dir>
./<binary> generate-ci-refs --org-repo <org/repo> --output-dir ci/step-registry
```

**3. No orphaned local refs**

Every `*-ref.yaml` in `<product>/ci/step-registry/` must map back to a suite in
`tests.json`. Orphaned refs indicate a suite was removed from the manifest but
the ref was not cleaned up.

```
[PASS] No orphaned local CI refs
[FAIL] Orphaned local CI ref: cnv-tests-cnv-legacy (no matching suite)
```

**4. Ref content is valid**

Each ref YAML is parsed and checked for:
- `from` field matches the product binary name
- `commands` file exists on disk
- `commands.sh` contains a `<binary> run-suite` invocation

```
[PASS] All local ref YAML and commands.sh are valid
[FAIL] Ref cnv-tests-cnv-all: from="wrong-binary", expected "cnv-tests"
[FAIL] Ref cnv-tests-cnv-smoke: commands file cnv-tests-cnv-smoke-commands.sh missing
```

### Phase 2: Upstream CI Checks (when `--ci-path` or `--ci-repo` is provided)

These checks compare OTE suites against upstream CI step-registry refs.

#### Using `--ci-path` (local clone)

Points to a local directory containing the CI step-registry. The tool
recursively walks `<ci-path>/<upstream-ci-dir>/` to find all `*-ref.yaml` files.

```bash
# Clone openshift/release first
git clone --depth 1 https://github.com/openshift/release.git /tmp/release

# Point to its step-registry
./ote-validate-ci --component cnv --ci-path /tmp/release/ci-operator/step-registry
```

#### Using `--ci-repo` (GitHub API)

Fetches refs directly from GitHub using the `gh` CLI. Requires `gh` to be
installed and authenticated (`gh auth login`).

```bash
./ote-validate-ci --component cnv --ci-repo openshift/release
```

The tool first checks the expected step-registry path
(`ci-operator/step-registry/<upstream-ci-dir>/`) in the repo. If that path does
not exist (e.g., the repo is not `openshift/release`), it falls back to scanning
the entire repo tree for any `*-ref.yaml` files.

```
[INFO] No step-registry path "ci-operator/step-registry/cnv" in RedHatQE/openshift-virtualization-tests, scanning full repo tree...
[INFO] No CI step-registry ref files (*-ref.yaml) found in RedHatQE/openshift-virtualization-tests
```

#### Upstream check output

Upstream refs are matched against OTE suites by ref name. The tool parses both
OTE-format and upstream CI-format YAML (which uses nested `ref.from_image`
instead of flat `from`).

```
[PASS] Upstream ref cnv-tests-cnv-all matches OTE suite cnv/all (image: cnv-tests)
[INFO] Upstream ref cnv-deploy-cnv (image: ocp-qe-perfscale-ci) -- no matching OTE suite
[WARN] OTE suite cnv/smoke has no upstream CI ref
```

## Output Markers

| Marker | Meaning | Affects exit code? |
|--------|---------|-------------------|
| `[PASS]` | Check passed | No |
| `[FAIL]` | Check failed | Yes (exit 1) |
| `[WARN]` | Potential issue, non-blocking | No |
| `[INFO]` | Informational | No |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checks passed (warnings are OK) |
| 1 | One or more checks failed |

## Examples

### Validate all products locally

```bash
./ote-validate-ci --all
```

```
=== Validating component: cnv ===
  Directory:  cnv-tests/
  Binary:     cnv-tests
  Tests:      3
  Suites:     2

  --- OTE Internal Checks ---
  [PASS] All 3 test scripts exist and are executable
  [PASS] Suite cnv/all -> local ref cnv-tests-cnv-all
  [PASS] Suite cnv/smoke -> local ref cnv-tests-cnv-smoke
  [PASS] No orphaned local CI refs
  [PASS] All local ref YAML and commands.sh are valid

  Result: all checks passed

=== Validating component: virt ===
  ...
```

### Compare CNV against upstream openshift/release

```bash
./ote-validate-ci --component cnv --ci-repo openshift/release
```

```
=== Validating component: cnv ===
  Directory:  cnv-tests/
  Binary:     cnv-tests
  Tests:      3
  Suites:     2

  --- OTE Internal Checks ---
  [PASS] All 3 test scripts exist and are executable
  [PASS] Suite cnv/all -> local ref cnv-tests-cnv-all
  [PASS] Suite cnv/smoke -> local ref cnv-tests-cnv-smoke
  [PASS] No orphaned local CI refs
  [PASS] All local ref YAML and commands.sh are valid

  --- Upstream CI Checks (--ci-repo openshift/release) ---
  [INFO] Upstream ref cnv-deploy-cnv (image: ocp-qe-perfscale-ci) -- no matching OTE suite
  [INFO] Upstream ref cnv-e2e (image: cnv-ci-src) -- no matching OTE suite
  [INFO] Upstream ref cnv-smoke-lvms (image: openshift-virtualization-tests) -- no matching OTE suite
  [WARN] OTE suite cnv/all has no upstream CI ref
  [WARN] OTE suite cnv/smoke has no upstream CI ref

  Result: all checks passed
```

### Check a repo that has no step-registry refs

```bash
./ote-validate-ci --component cnv --ci-repo https://github.com/RedHatQE/openshift-virtualization-tests
```

```
  --- Upstream CI Checks (--ci-repo RedHatQE/openshift-virtualization-tests) ---
  [INFO] No step-registry path "ci-operator/step-registry/cnv" in RedHatQE/openshift-virtualization-tests, scanning full repo tree...
  [INFO] No CI step-registry ref files (*-ref.yaml) found in RedHatQE/openshift-virtualization-tests
```

## Fixing Common Failures

### Missing local CI refs

```
[FAIL] Suite cnv/smoke has no local CI ref (expected: cnv-tests-cnv-smoke)
```

Regenerate refs:

```bash
cd cnv-tests
./cnv-tests generate-ci-refs --org-repo openshift/cnv-tests --output-dir ci/step-registry
```

### Orphaned local refs

```
[FAIL] Orphaned local CI ref: cnv-tests-cnv-legacy (no matching suite)
```

Delete the orphaned files:

```bash
rm cnv-tests/ci/step-registry/cnv-tests-cnv-legacy-ref.yaml
rm cnv-tests/ci/step-registry/cnv-tests-cnv-legacy-commands.sh
```

### Ref content mismatch

```
[FAIL] Ref cnv-tests-cnv-all: from="wrong-binary", expected "cnv-tests"
```

Regenerate refs (this overwrites existing files with correct values):

```bash
cd cnv-tests
./cnv-tests generate-ci-refs --org-repo openshift/cnv-tests --output-dir ci/step-registry
```

### gh CLI not found

```
[WARN] gh CLI not found -- install GitHub CLI to enable upstream checks
```

Install the GitHub CLI and authenticate:

```bash
# macOS
brew install gh

# RHEL/Fedora
dnf install gh

# Authenticate
gh auth login
```

## Prerequisites

- The product binary does not need to be built; the tool reads `tests.json`
  and `ci/step-registry/` directly from the filesystem.
- For `--ci-repo`: the `gh` CLI must be installed and authenticated.
- For `--ci-path`: a local clone of the target repo (e.g., `openshift/release`).

## CI Integration

Add to your Makefile or CI script:

```bash
# Build the tool
make ote-validate-ci

# Run as part of CI (exit code 1 fails the job on any FAIL)
./ote-validate-ci --all
```

For upstream comparison in CI (requires `gh` auth token):

```bash
./ote-validate-ci --all --ci-repo openshift/release
```
