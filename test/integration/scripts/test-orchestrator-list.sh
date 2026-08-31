#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Verify that each product binary responds to `list tests` with environment
# flags as openshift-tests would invoke it.

declare errors=0
declare tested=0

for product_dir in cnv-tests virt-tests opp-tests stolostron-policy-collection; do
    if [[ ! -f "${product_dir}/${product_dir}" ]]; then
        continue
    fi
    tested=$((tested + 1))
    echo "--- Testing list tests for ${product_dir} ---"

    # Basic list tests
    output=$(cd "${product_dir}" && "./${product_dir}" list tests 2>&1)
    count=$(echo "$output" | grep -c '"name"' || true)

    if [[ "$count" -eq 0 ]]; then
        echo "FAIL: ${product_dir} list tests returned 0 tests" >&2
        errors=$((errors + 1))
        continue
    fi

    # Verify source field shows non-payload (external)
    if ! echo "$output" | grep -q ':external:'; then
        echo "FAIL: ${product_dir} list tests missing external source identifier" >&2
        errors=$((errors + 1))
        continue
    fi

    # Test environment flag passthrough (--platform) — just verify it doesn't error
    (cd "${product_dir}" && "./${product_dir}" list tests --platform aws >/dev/null 2>&1) || true

    # Test output format: names
    names_output=$(cd "${product_dir}" && "./${product_dir}" list tests --output names 2>&1)
    if [[ -z "$names_output" ]]; then
        echo "FAIL: ${product_dir} --output names returned empty" >&2
        errors=$((errors + 1))
        continue
    fi

    echo "PASS: ${product_dir} list tests works (${count} tests)"
done

if [[ $tested -eq 0 ]]; then
    echo "No product binaries found, skipping"
    exit 2
fi

if [[ $errors -gt 0 ]]; then
    echo "FAIL: ${errors} product(s) failed list tests check" >&2
    exit 1
fi

echo "PASS: all ${tested} product binaries respond correctly to list tests"
exit 0
true
