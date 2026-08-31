#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare tmpDir
tmpDir=$(mktemp -d)
declare projectName="scaffold-test-$$"

cp ote-scaffold.sh "${tmpDir}/"
cd "${tmpDir}"

./ote-scaffold.sh --name "${projectName}" --product testprod --org testorg \
    --ci-org-repo testorg/testprod

if [[ ! -f "${projectName}/cmd/${projectName}/main.go" ]]; then
    echo "FAIL: main.go not generated" >&2
    exit 1
fi

if [[ ! -f "${projectName}/tests.json" ]]; then
    echo "FAIL: tests.json not generated" >&2
    exit 1
fi

if [[ ! -f "${projectName}/Makefile" ]]; then
    echo "FAIL: Makefile not generated" >&2
    exit 1
fi

if [[ ! -f "${projectName}/Dockerfile" ]]; then
    echo "FAIL: Dockerfile not generated" >&2
    exit 1
fi

if [[ ! -x "${projectName}/scripts/example-pass.sh" ]]; then
    echo "FAIL: example-pass.sh not executable" >&2
    exit 1
fi

if [[ ! -f "${projectName}/ci/step-registry/testprod-testprod-all-ref.yaml" ]]; then
    echo "FAIL: CI step registry refs not generated" >&2
    exit 1
fi

if ! grep -q '"external"' "${projectName}/cmd/${projectName}/main.go"; then
    echo "FAIL: generated code should use non-payload external kind" >&2
    exit 1
fi

rm -rf "${tmpDir}"
echo "PASS: scaffold generates all expected files"
exit 0
true
