#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true
echo "This test fails" >&2
exit 1
true
