#!/usr/bin/env bash
set -euo pipefail

readonly IMAGE="diffblue/cbmc:6.10.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly MODEL="bugs/10-polyself-reentrant-form-changes/proof/polyself_model.c"

run_cbmc() {
    docker run --rm \
        -v "${REPO_ROOT}:/src:ro" \
        -w /src \
        "${IMAGE}" \
        cbmc "${MODEL}" \
        --function "$1" \
        --bounds-check \
        --pointer-check \
        --div-by-zero-check \
        --signed-overflow-check \
        --unsigned-overflow-check \
        --unwinding-assertions \
        "${@:2}"
}

expect_pass() {
    local name="$1"
    shift
    echo "PASS expected: ${name}"
    run_cbmc "$@"
}

expect_fail() {
    local name="$1"
    shift
    echo "FAIL expected: ${name}"
    set +e
    run_cbmc "$@"
    local status=$?
    set -e
    if [[ ${status} -eq 0 ]]; then
        echo "negative control unexpectedly passed: ${name}" >&2
        return 1
    fi
    if [[ ${status} -ne 10 ]]; then
        echo "CBMC failed operationally (${status}): ${name}" >&2
        return "${status}"
    fi
}

# Immediate light bookkeeping is sufficient; the old delayed scheme is not.
expect_pass "immediate light bookkeeping" \
    verify_light_bookkeeping
expect_fail "legacy delete-before-create window" \
    reject_delayed_light_bookkeeping

# Epoch guards prove the ownership property under arbitrary nested changes,
# including same-form reinstallations.
expect_pass "polymon epoch guards, including ABA" \
    verify_polymon_guards -DGUARD_MODE=2
expect_pass "break_armor epoch guards, including ABA" \
    verify_break_armor_guards -DGUARD_MODE=2

# The PR's identity guards pass only under an explicit no-ABA assumption.
expect_pass "polymon identity guards under no-ABA contract" \
    verify_polymon_guards -DGUARD_MODE=1 -DALLOW_SAME_FORM_REENTRY=0
expect_pass "break_armor identity guards under no-ABA contract" \
    verify_break_armor_guards -DGUARD_MODE=1 -DALLOW_SAME_FORM_REENTRY=0
expect_fail "polymon identity guard does not itself exclude ABA" \
    verify_polymon_guards -DGUARD_MODE=1 -DALLOW_SAME_FORM_REENTRY=1
expect_fail "break_armor identity guard does not itself exclude ABA" \
    verify_break_armor_guards -DGUARD_MODE=1 -DALLOW_SAME_FORM_REENTRY=1
expect_fail "reachable same-form polymorph-trap route defeats identity" \
    verify_same_form_polytrap_route -DGUARD_MODE=1
expect_pass "epoch guard detects same-form polymorph-trap route" \
    verify_same_form_polytrap_route -DGUARD_MODE=2

# Every proposed guard must be independently necessary.  Force an ordinary
# A -> human invalidation at that boundary and omit just that guard.
for boundary in 0 1 2 3 4; do
    expect_fail "polymon omitted guard ${boundary}" \
        verify_polymon_guards -DGUARD_MODE=1 \
        -DALLOW_SAME_FORM_REENTRY=0 \
        -DFORCE_BOUNDARY="${boundary}" -DOMIT_GUARD="${boundary}"
done

for boundary in 5 6 7; do
    expect_fail "break_armor omitted guard ${boundary}" \
        verify_break_armor_guards -DGUARD_MODE=1 \
        -DALLOW_SAME_FORM_REENTRY=0 \
        -DFORCE_BOUNDARY="${boundary}" -DOMIT_GUARD="${boundary}"
done

echo "CBMC pilot matrix completed successfully"
