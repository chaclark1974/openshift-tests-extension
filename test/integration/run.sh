#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

declare scriptDir
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare repoRoot
repoRoot="$(cd "${scriptDir}/../.." && pwd)"

cd "${repoRoot}"

echo "=== Building fixture-tests binary ==="
GO_COMPLIANCE_POLICY="exempt_all" go build -o fixture-tests ./cmd/fixture-tests/...

echo "=== Building integration-tests binary ==="
GO_COMPLIANCE_POLICY="exempt_all" go build -o integration-tests ./test/integration/cmd/integration-tests/...

echo "=== Verifying fixture-tests binary ==="
./fixture-tests info
./fixture-tests list tests | head -20

echo "=== Running integration test suite ==="
./integration-tests run-suite integration/all

declare exitCode=$?

rm -f fixture-tests integration-tests

exit "${exitCode}"
true
