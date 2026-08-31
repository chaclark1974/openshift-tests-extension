#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true
echo "Skipping test" >&2
exit 2
true
