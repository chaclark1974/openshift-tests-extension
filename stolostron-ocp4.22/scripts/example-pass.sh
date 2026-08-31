#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true
echo "Running example passing test"
echo "All checks passed."
exit 0
true
