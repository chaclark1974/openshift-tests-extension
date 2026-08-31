#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

cnv-tests run-suite cnv/smoke
true
