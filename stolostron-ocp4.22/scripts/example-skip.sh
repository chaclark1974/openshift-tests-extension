#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true
if [[ -z "${REQUIRED_ENV_VAR:-}" ]]; then
    echo "REQUIRED_ENV_VAR not set, skipping test"
    exit 2
fi
echo "Running test with REQUIRED_ENV_VAR=${REQUIRED_ENV_VAR}"
exit 0
true
