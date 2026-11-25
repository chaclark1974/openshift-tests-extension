# Container Images for ote--interop

## Dockerfile.ci

Production container image for the ote--interop binary.

### Build

```bash
# From repository root
docker build -f interop/test/ote/images/Dockerfile.ci -t ote-interop:latest .

# Or from ote directory
cd interop/test/ote
docker build -f images/Dockerfile.ci -t ote-interop:latest ../../..
```

### Run

```bash
# List components
docker run --rm ote-interop:latest list components

# List tests
docker run --rm ote-interop:latest list tests --output names

# Run with kubeconfig (mount volume)
docker run --rm \
  -v ~/.kube/config:/tmp/kubeconfig:ro \
  -e KUBECONFIG=/tmp/kubeconfig \
  ote-interop:latest run-suite acm/smoke
```

### Image Contents

- **Binary:** `/usr/local/bin/ote--interop`
- **Test-suites:** `/opt/ote/test-suites/`
- **Environment:** `OTE_TEST_SUITES_DIR=/opt/ote/test-suites`

### For CI

The image is built in openshift/release via ci-operator:

```yaml
images:
- dockerfile_path: interop/test/ote/images/Dockerfile.ci
  to: ote-interop
```

The binary is extracted and used in test steps:

```bash
oc image extract "${OTE_INTEROP_IMAGE}" \
  --path /usr/local/bin/ote--interop:/usr/local/bin/ \
  --confirm
```
