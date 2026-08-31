#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if [[ -n "${TEST_ARTIFACTS_DIR:-}" ]]; then
    echo "test artifact content" > "${TEST_ARTIFACTS_DIR}/test-output.txt"
    echo "Wrote artifact to ${TEST_ARTIFACTS_DIR}"
fi
exit 0
true
