# Test Suites - Runtime Assets

This directory contains the **runtime test assets** (scripts, manifests, configs) referenced by scenarios in `../scenarios/`.

## Directory Structure

Each test is a **leaf directory** containing an `ote.sh` script:

```
test-suites/
├── acm/
│   ├── policy-set/
│   │   ├── opp-bundle/
│   │   │   └── deployment/
│   │   │       ├── ote.sh          ← test runner script
│   │   │       └── OWNERS
│   │   └── security-scan/
│   │       └── ctr-img/
│   │           └── acs/
│   │               └── app-deployment/
│   │                   ├── ote.sh
│   │                   └── OWNERS
├── acs/
├── cnv/
├── odf/
└── quay/
    └── smoke/
        └── acs-odf/
            └── registry/
                ├── ote.sh
                └── OWNERS
```

## Naming Convention

**Use `ote.sh` for all test scripts** (not duplicated long names).

✅ **Correct:**
```
deployment/
├── ote.sh
└── OWNERS
```

❌ **Avoid (duplication):**
```
deployment/
├── interop-acm-policy-set-opp-bundle-deployment-commands.sh
├── interop-acm-policy-set-opp-bundle-deployment-ref.yaml
└── OWNERS
```

**Rationale:** The directory path already encodes the test identity. Using the same script name (`ote.sh`) eliminates duplication and follows DRY principles.

## Wiring Scenarios to Test Suites

Scenarios reference test-suites via `workDir` and `command`:

```json
{
  "name": "[sig-acm-policy-set] PolicySet applies grouped policies",
  "product": "acm",
  "category": "acm-policy-set",
  "workDir": "${OTE_TEST_SUITES_DIR}/acm/policy-set/opp-bundle/deployment",
  "command": ["bash", "ote.sh"],
  "skipIfEnvUnset": ["KUBECONFIG"]
}
```

## Runtime Environment

**`OTE_TEST_SUITES_DIR`** must point to this directory at runtime:

```bash
# Local development
export OTE_TEST_SUITES_DIR="/home/user/ote-interop/test-suites"
make test

# CI (Dockerfile.ci should copy test-suites to this location)
COPY test-suites /opt/ote/test-suites
ENV OTE_TEST_SUITES_DIR=/opt/ote/test-suites
```

Default: `$HOME/ote` (can be overridden via Makefile or environment)

## Script Requirements

Each `ote.sh` must:

1. ✅ **Exit 0 on success**, non-zero on failure
2. ✅ **Print clear status messages** (INFO/PASS/FAIL/SKIP)
3. ✅ **Handle missing dependencies gracefully** (skip if not applicable)
4. ✅ **Be idempotent** (safe to run multiple times)
5. ✅ **Follow bash best practices** (`set -euo pipefail`)

**Example:**

```bash
#!/bin/bash
set -euo pipefail

echo "INFO: Checking for ACM PolicySet CRD..."

if ! oc get crd policysets.policy.open-cluster-management.io &>/dev/null; then
    echo "FAIL: PolicySet CRD not found"
    exit 1
fi

echo "PASS: PolicySet CRD is installed"
exit 0
```

## Adding a New Test

1. **Create directory structure:**
   ```bash
   mkdir -p test-suites/acm/new-area/new-test
   ```

2. **Create `ote.sh`:**
   ```bash
   cat > test-suites/acm/new-area/new-test/ote.sh << 'EOF'
   #!/bin/bash
   set -euo pipefail
   echo "INFO: Running new test..."
   # test logic here
   exit 0
   EOF
   chmod +x test-suites/acm/new-area/new-test/ote.sh
   ```

3. **Create `OWNERS`:**
   ```bash
   cat > test-suites/acm/new-area/new-test/OWNERS << 'EOF'
   approvers:
     - cspi-qe-ocp-lp
   reviewers:
     - cspi-qe-ocp-lp
   EOF
   ```

4. **Add scenario** in `scenarios/acm/scenarios.json`:
   ```json
   {
     "name": "[sig-acm-new-area] Description",
     "product": "acm",
     "category": "acm-new-area",
     "workDir": "${OTE_TEST_SUITES_DIR}/acm/new-area/new-test",
     "command": ["bash", "ote.sh"]
   }
   ```

5. **Rebuild:**
   ```bash
   make build
   ```

## Testing Locally

```bash
# Set environment
export OTE_TEST_SUITES_DIR="$(pwd)/test-suites"
export KUBECONFIG=~/.kube/config

# Run specific test
./ote--interop run-test "[sig-acm-policy-set] PolicySet applies grouped policies"

# Run suite
./ote--interop run-suite acm/policy-set/opp-bundle/deployment
```

## See Also

- `../scenarios/` - Embedded test catalogs (JSON)
- `../IMPLEMENTATION.md` - Complete architecture reference
- `../README.md` - Quick start guide
