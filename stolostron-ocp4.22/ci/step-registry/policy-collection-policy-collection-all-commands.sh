#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

stolostron-ocp4.22 run-suite policy-collection/all
true
