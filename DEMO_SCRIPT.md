# OTE Shell Test Onboarding Framework — Sprint Demo Script

## Demo Overview

This demo covers the full framework lifecycle: scaffold, manifest, build, test,
CI integration, and openshift-tests orchestrator protocol.

**Duration**: ~15 minutes

---

## 1. Framework Overview (2 min)

Show the architecture diagram:

```
ote-scaffold.sh (or ote-onboard)
        |
        v
product-tests/
├── cmd/product-tests/main.go    ← generated (no Go needed)
├── scripts/*.sh                  ← team writes shell tests
├── tests.json                    ← declarative manifest
├── Makefile                      ← generated (build/test/ci/image)
└── Dockerfile                    ← generated (UBI9 multi-stage)
```

Key points:
- Non-payload path only (`NewExtension("product", "external", "name")`)
- No Ginkgo — pure shell scripts
- Exit codes: 0=pass, 2=skip, non-zero=fail
- `tests.json` is the only file teams edit

## 2. Live Demo: Scaffold a New Product (3 min)

```bash
# Interactive mode
./ote-onboard

# Or non-interactive
./ote-scaffold.sh --name demo-tests --product demo \
  --org github.com/openshift-eng --kind external \
  --ci-org-repo openshift/demo-tests

cd demo-tests
go mod tidy
make build
make validate
```

Show the output:
- `info` — confirms external/non-payload
- `list tests` — 2 example tests
- `list suites` — demo/all, demo/smoke

## 3. Show Onboarded Products (3 min)

```bash
# CNV — 3 tests, 2 suites
cd cnv-tests && ./cnv-tests info && ./cnv-tests list tests --output names

# Virt — 8 tests, 3 suites
cd virt-tests && ./virt-tests list tests --output names && ./virt-tests list suites

# OPP — 15 tests, 8 suites (mirrors interop-opp-aws)
cd opp-tests && ./opp-tests list suites

# Policy Collection — 12 tests, 4 suites (NIST 800-53)
cd stolostron-policy-collection && ./stolostron-policy-collection list tests --output names
```

Total: **38 tests across 4 products**, all running on the same framework.

## 4. Run Tests with JUnit/HTML Output (2 min)

```bash
cd opp-tests
ARTIFACT_DIR=/tmp/artifacts make test
ls /tmp/artifacts/
# → junit_opp_<timestamp>.xml, results-opp-<timestamp>.html
```

Show the HTML report in a browser.

## 5. openshift-tests Orchestrator Protocol (2 min)

Demonstrate the protocol that openshift-tests uses:

```bash
# Step 1: Discovery
./cnv-tests info | jq '.component'

# Step 2: Test listing with environment filters
./cnv-tests list tests --platform aws --architecture amd64

# Step 3: Execute a single test
./cnv-tests run-test "[sig-cnv] CNV operator is running and available"
# → JSON result with name, result, duration, output

# Step 4: Suite execution
./cnv-tests run-suite cnv/smoke
```

## 6. CI Pipeline (2 min)

```bash
# Full CI target: build + validate + shellcheck
make ci

# Container image
make image

# Step registry refs
./cnv-tests generate-ci-refs --org-repo openshift/cnv-tests --output-dir ci/step-registry
ls ci/step-registry/
```

## 7. Regression Test Results (1 min)

```
Go unit tests:       all pass
Framework tests:     15/15 pass
Integration tests:   17/17 pass (including 5 orchestrator protocol tests)
Shellcheck:          all scripts clean
Product validation:  4/4 products validate
Smoke suites:        4/4 skip gracefully (no cluster)
```

---

## Handoff Checklist

### For Each Product QE Team

- [ ] Clone `openshift-tests-extension` repo
- [ ] Navigate to your product directory (e.g., `cnv-tests/`)
- [ ] Run `go mod tidy && make build && make validate` to verify
- [ ] Read `README.md` for product-specific instructions
- [ ] Read `ONBOARDING_SHELL_TESTS.md` for the full onboarding guide
- [ ] Add new test scripts to `scripts/` and register in `tests.json`
- [ ] Run `make ci` to verify build + validate + lint
- [ ] Run `make test` to execute your suite (requires cluster for real results)

### Product Ownership

| Product | Binary | Tests | Owner |
|---------|--------|-------|-------|
| CNV | `cnv-tests` | 3 | CNV QE |
| Virt | `virt-tests` | 8 | Virt QE |
| OPP | `opp-tests` | 15 | OPP QE |
| Policy Collection | `stolostron-policy-collection` | 12 | ACM QE |

### Key Resources

| Resource | Location |
|----------|----------|
| Onboarding guide | `ONBOARDING_SHELL_TESTS.md` |
| Scaffold tool | `ote-scaffold.sh` or `ote-onboard` |
| Shared library | `pkg/shell/` |
| CI templates | `ci/` |
| Schema | `tests.schema.json` |

### Adding Tests (self-service)

Teams can add tests independently without framework changes:

1. Write a shell script in `scripts/`
2. Add an entry to `tests.json`
3. Run `make ci` to validate
4. Submit PR
