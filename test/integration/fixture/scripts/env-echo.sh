#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true
echo "MY_TEST_VAR=${MY_TEST_VAR:-unset}"
exit 0
true
