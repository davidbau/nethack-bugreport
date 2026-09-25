#!/usr/bin/env bash
# run-wp.sh — Frama-C/WP proof of polyself_acsl.c, plus one negative control.
#
# 1. Proof: WP generates and discharges goals for EVERY function in the file.
#    (An earlier version passed -wp-fct with only the two top-level entry
#    points; WP then assumed the contracts of the functions they call, so the
#    boundary lemma in generation_boundary_arbitrary_aba() was never checked.)
#    The run passes only if every goal is proved AND the property report has
#    nothing "To be validated", i.e. no property is merely assumed.
#
# 2. Negative control: with -DIDENTITY_MAX_CHOICE=3 the identity-guard model
#    admits a callback that reinstalls the same form (ABA).  WP must then fail
#    to prove exactly one goal, the identity boundary's `assert choice == 0`.
set -euo pipefail

readonly IMAGE="framac/frama-c:32.1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly MODEL="bugs/10-polyself-reentrant-form-changes/proof/polyself_acsl.c"
readonly OUTPUT="$(mktemp)"
trap 'rm -f "${OUTPUT}"' EXIT

run_wp() {
    docker run --rm \
        -v "${REPO_ROOT}:/src:ro" \
        -w /src \
        "${IMAGE}" \
        frama-c "${MODEL}" "$@" \
        -wp \
        -wp-rte \
        -wp-prover qed,alt-ergo \
        -wp-timeout 120 \
        -then -report 2>&1 | tee "${OUTPUT}"
}

goal_counts() {
    local summary
    summary="$(grep -Eo 'Proved goals:[[:space:]]+[0-9]+ / [0-9]+' "${OUTPUT}" | tail -n 1)"
    if [[ -z "${summary}" ]]; then
        echo "Frama-C/WP did not print a proof summary" >&2
        exit 1
    fi
    awk '{print $(NF-2), $NF}' <<<"${summary}"
}

echo "=== WP proof: every function in the model ==="
run_wp
read -r proved total < <(goal_counts)
if [[ "${proved}" != "${total}" ]]; then
    echo "Frama-C/WP left proof obligations open: ${proved}/${total}" >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*[0-9]+ To be validated' "${OUTPUT}"; then
    echo "Frama-C/WP proved its goals, but some properties were only assumed:" >&2
    grep -E 'To be validated|\[ *- *\]' "${OUTPUT}" >&2
    exit 1
fi
echo "Frama-C/WP discharged every proof obligation: ${proved}/${total}, none assumed"

echo
echo "=== WP negative control: identity guards with a same-form reinstall ==="
set +e
run_wp -cpp-extra-args=-DIDENTITY_MAX_CHOICE=3 >/dev/null
set -e
read -r proved total < <(goal_counts)
unproved="$(grep -E '^\[wp\] \[(Timeout|Unknown|Failed)\]' "${OUTPUT}" | awk '{print $3}')"
if [[ "${unproved}" != "typed_identity_boundary_no_aba_assert" ]]; then
    echo "negative control: expected only typed_identity_boundary_no_aba_assert" >&2
    echo "to be unproved, got: ${unproved:-(nothing)} (${proved}/${total})" >&2
    exit 1
fi
echo "negative control behaved as expected: ${proved}/${total}; the one open goal is"
echo "  ${unproved}  (identity guards cannot tell a same-form reinstall from no change)"
