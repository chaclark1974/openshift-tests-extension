#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Verify that each product binary responds to `run-test` with JSON results
# as openshift-tests would invoke it. Without a live cluster, tests should
# skip (exit 2) or fail — both are valid protocol responses.

declare errors=0
declare tested=0

for product_dir in cnv-tests virt-tests opp-tests stolostron-policy-collection; do
    if [[ ! -f "${product_dir}/${product_dir}" ]]; then
        continue
    fi
    tested=$((tested + 1))
    echo "--- Testing run-test for ${product_dir} ---"

    # Get first test name
    first_test=$(cd "${product_dir}" && "./${product_dir}" list tests --output names 2>/dev/null | head -1)
    if [[ -z "$first_test" ]]; then
        echo "FAIL: ${product_dir} has no tests to run" >&2
        errors=$((errors + 1))
        continue
    fi

    # Run the test — expect skip or fail since no cluster
    output=$(cd "${product_dir}" && "./${product_dir}" run-test "${first_test}" 2>&1) || true

    # Result must contain JSON with "result" field
    if ! echo "$output" | grep -q '"result"'; then
        echo "FAIL: ${product_dir} run-test missing 'result' field in output" >&2
        echo "Output: ${output}" >&2
        errors=$((errors + 1))
        continue
    fi

    # Verify duration field is present
    if ! echo "$output" | grep -q '"duration"'; then
        echo "FAIL: ${product_dir} run-test missing 'duration' field" >&2
        errors=$((errors + 1))
        continue
    fi

    # Verify name field is present
    if ! echo "$output" | grep -q '"name"'; then
        echo "FAIL: ${product_dir} run-test missing 'name' field" >&2
        errors=$((errors + 1))
        continue
    fi

    echo "PASS: ${product_dir} run-test produces valid JSON result"
done

if [[ $tested -eq 0 ]]; then
    echo "No product binaries found, skipping"
    exit 2
fi

if [[ $errors -gt 0 ]]; then
    echo "FAIL: ${errors} product(s) failed run-test check" >&2
    exit 1
fi

echo "PASS: all ${tested} product binaries produce valid run-test results"
exit 0
true
