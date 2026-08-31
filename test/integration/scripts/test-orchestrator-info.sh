#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Verify that each product binary responds correctly to the `info` command
# as openshift-tests would call it during discovery.

declare errors=0
declare tested=0

for product_dir in cnv-tests virt-tests opp-tests stolostron-policy-collection; do
    if [[ ! -f "${product_dir}/${product_dir}" ]]; then
        continue
    fi
    tested=$((tested + 1))
    echo "--- Testing info for ${product_dir} ---"

    output=$(cd "${product_dir}" && "./${product_dir}" info 2>&1)

    if ! echo "$output" | grep -q '"apiVersion"'; then
        echo "FAIL: ${product_dir} info missing apiVersion" >&2
        errors=$((errors + 1))
        continue
    fi

    if ! echo "$output" | grep -q '"type": "external"'; then
        echo "FAIL: ${product_dir} info missing type external" >&2
        errors=$((errors + 1))
        continue
    fi

    if ! echo "$output" | grep -q '"suites"'; then
        echo "FAIL: ${product_dir} info missing suites" >&2
        errors=$((errors + 1))
        continue
    fi

    echo "PASS: ${product_dir} info is valid"
done

if [[ $tested -eq 0 ]]; then
    echo "No product binaries found, skipping"
    exit 2
fi

if [[ $errors -gt 0 ]]; then
    echo "FAIL: ${errors} product(s) failed info check" >&2
    exit 1
fi

echo "PASS: all ${tested} product binaries respond correctly to info"
exit 0
true
