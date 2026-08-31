#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

virt-tests run-suite virt/smoke
true
