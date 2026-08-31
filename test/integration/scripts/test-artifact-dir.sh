#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare artifactDir
artifactDir=$(mktemp -d)
export EXTENSION_ARTIFACTS_DIR="${artifactDir}"

declare output
output=$(./fixture-tests run-test "[sig-fixture] artifact test" 2>&1) || true

if ! echo "$output" | grep -q '"passed"'; then
    echo "FAIL: artifact test should pass" >&2
    exit 1
fi

declare testArtifactDir="${artifactDir}/sig-fixture-artifact-test"
if [[ ! -f "${testArtifactDir}/test-output.txt" ]]; then
    echo "FAIL: expected test-output.txt in artifact dir" >&2
    ls -la "${artifactDir}/" >&2
    exit 1
fi

if [[ ! -f "${testArtifactDir}/stdout.log" ]]; then
    echo "FAIL: expected stdout.log in artifact dir" >&2
    exit 1
fi

if ! echo "$output" | grep -q 'Artifacts:'; then
    echo "FAIL: expected artifact summary in output" >&2
    exit 1
fi

rm -rf "${artifactDir}"
echo "PASS: artifact directory created with content"
exit 0
true
