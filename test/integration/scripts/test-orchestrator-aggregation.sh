#!/bin/bash
set -euxo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Verify that results from multiple product binaries can be aggregated
# as openshift-tests would do.

declare tmpdir
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

declare errors=0
declare total_tests=0
declare tested=0

for product_dir in cnv-tests virt-tests opp-tests stolostron-policy-collection; do
    if [[ ! -f "${product_dir}/${product_dir}" ]]; then
        continue
    fi
    tested=$((tested + 1))

    # Get first test name
    first_test=$(cd "${product_dir}" && "./${product_dir}" list tests --output names 2>/dev/null | head -1)
    if [[ -z "$first_test" ]]; then
        echo "WARN: ${product_dir} has no tests" >&2
        continue
    fi

    # Run-test and capture result
    (cd "${product_dir}" && "./${product_dir}" run-test "${first_test}") > "${tmpdir}/${product_dir}.json" 2>&1 || true
    total_tests=$((total_tests + 1))
done

if [[ $tested -lt 2 ]]; then
    echo "Need at least 2 product binaries for aggregation test, skipping"
    exit 2
fi

# Aggregate: verify all result files exist and contain valid JSON
declare aggregated=0
for f in "${tmpdir}"/*.json; do
    if [[ ! -f "$f" ]]; then
        continue
    fi
    if ! grep -q '"result"' "$f"; then
        echo "FAIL: $(basename "$f") missing result field" >&2
        errors=$((errors + 1))
        continue
    fi
    aggregated=$((aggregated + 1))
done

if [[ $aggregated -ne $total_tests ]]; then
    echo "FAIL: expected ${total_tests} results, aggregated ${aggregated}" >&2
    exit 1
fi

if [[ $errors -gt 0 ]]; then
    echo "FAIL: ${errors} aggregation errors" >&2
    exit 1
fi

echo "PASS: ${aggregated} product results aggregated successfully"
exit 0
true
