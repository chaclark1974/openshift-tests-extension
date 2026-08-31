#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare outputDir
outputDir=$(mktemp -d)

./fixture-tests generate-ci-refs \
    --org-repo openshift/fixture-tests \
    --output-dir "${outputDir}"

if [[ ! -f "${outputDir}/fixture-tests-fixture-all-ref.yaml" ]]; then
    echo "FAIL: expected fixture-all ref yaml" >&2
    ls -la "${outputDir}/" >&2
    exit 1
fi

if [[ ! -f "${outputDir}/fixture-tests-fixture-all-commands.sh" ]]; then
    echo "FAIL: expected fixture-all commands.sh" >&2
    exit 1
fi

if [[ ! -f "${outputDir}/fixture-tests-fixture-smoke-ref.yaml" ]]; then
    echo "FAIL: expected fixture-smoke ref yaml" >&2
    exit 1
fi

if ! grep -q 'from: fixture-tests' "${outputDir}/fixture-tests-fixture-all-ref.yaml"; then
    echo "FAIL: ref yaml missing from field" >&2
    exit 1
fi

if ! grep -q 'run-suite fixture/all' "${outputDir}/fixture-tests-fixture-all-commands.sh"; then
    echo "FAIL: commands.sh missing run-suite command" >&2
    exit 1
fi

rm -rf "${outputDir}"
echo "PASS: generate-ci-refs produces correct output"
exit 0
true
