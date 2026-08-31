#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Verify that each product binary lists suites and components correctly.

declare errors=0
declare tested=0

for product_dir in cnv-tests virt-tests opp-tests stolostron-policy-collection; do
    if [[ ! -f "${product_dir}/${product_dir}" ]]; then
        continue
    fi
    tested=$((tested + 1))
    echo "--- Testing suites for ${product_dir} ---"

    # list suites must return output
    suites_output=$(cd "${product_dir}" && "./${product_dir}" list suites 2>&1)
    if [[ -z "$suites_output" ]]; then
        echo "FAIL: ${product_dir} list suites returned empty" >&2
        errors=$((errors + 1))
        continue
    fi

    # Must contain at least a "smoke" suite
    if ! echo "$suites_output" | grep -qi 'smoke'; then
        echo "FAIL: ${product_dir} list suites missing smoke suite" >&2
        errors=$((errors + 1))
        continue
    fi

    # list components must return output
    comp_output=$(cd "${product_dir}" && "./${product_dir}" list components 2>&1)
    if [[ -z "$comp_output" ]]; then
        echo "FAIL: ${product_dir} list components returned empty" >&2
        errors=$((errors + 1))
        continue
    fi

    echo "PASS: ${product_dir} suites and components listed correctly"
done

if [[ $tested -eq 0 ]]; then
    echo "No product binaries found, skipping"
    exit 2
fi

if [[ $errors -gt 0 ]]; then
    echo "FAIL: ${errors} product(s) failed suite listing check" >&2
    exit 1
fi

echo "PASS: all ${tested} product binaries list suites correctly"
exit 0
true
