#!/usr/bin/env bash
set -euo pipefail

readonly IMAGE="framac/frama-c:32.1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly OUTPUT="$(mktemp)"
trap 'rm -f "${OUTPUT}"' EXIT

docker run --rm \
    -v "${REPO_ROOT}:/src:ro" \
    -w /src \
    "${IMAGE}" \
    frama-c bugs/10-polyself-reentrant-form-changes/proof/polyself_acsl.c \
    -wp \
    -wp-fct verify_polymon_generation_arbitrary_aba,verify_break_armor_generation_arbitrary_aba \
    -wp-rte \
    -wp-prover qed,alt-ergo \
    -wp-timeout 120 2>&1 | tee "${OUTPUT}"

summary="$(grep -Eo 'Proved goals:[[:space:]]+[0-9]+ / [0-9]+' "${OUTPUT}" | tail -n 1)"
if [[ -z "${summary}" ]]; then
    echo "Frama-C/WP did not print a proof summary" >&2
    exit 1
fi

proved="$(awk '{print $(NF-2)}' <<<"${summary}")"
total="$(awk '{print $NF}' <<<"${summary}")"
if [[ "${proved}" != "${total}" ]]; then
    echo "Frama-C/WP left proof obligations open: ${summary}" >&2
    exit 1
fi

echo "Frama-C/WP discharged every proof obligation: ${proved}/${total}"
