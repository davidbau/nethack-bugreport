#!/usr/bin/env bash
# run-wp.sh — Frama-C/WP proof of the generation invariant (polyself_acsl.c),
# plus negative controls that must fail.
#
# 1. Proof: WP checks EVERY function in the file against its contract, and
#    the run passes only if every goal is proved and no property is left
#    "To be validated" (merely assumed).
#
# 2. Negative controls, each a small edit of the model that must make WP
#    fail, so the proof cannot be passing for lack of anything to find:
#      - each of the eight checkpoints in turn has its answer ignored (a
#        stale call keeps going);
#      - install_form() stops bumping the counter;
#      - the identity guard loses its "never reinstall the owner's form"
#        promise (-DIDENTITY_ALLOW_REINSTALL): exactly one goal, its
#        "assert owns(g)", must stay unproved.
set -euo pipefail

readonly IMAGE="framac/frama-c:32.1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MODEL="${SCRIPT_DIR}/polyself_acsl.c"
readonly WORK="$(mktemp -d)"
chmod 755 "${WORK}"   # the container runs as another user
# Clean up by file name and rmdir (which only removes an empty directory),
# never by a recursive delete of a computed path.
trap 'rm -f "${WORK}"/*.c "${WORK}/log"; rmdir "${WORK}"' EXIT

# wp FILE [frama-c options...] -- prove FILE (a name inside ${WORK}); the
# full log is left in ${WORK}/log.
wp() {
    local file="$1"
    shift
    docker run --rm \
        -v "${WORK}:/src:ro" \
        -w /src \
        "${IMAGE}" \
        frama-c "${file}" "$@" \
        -wp -wp-rte -wp-prover qed,alt-ergo -wp-timeout 30 \
        -then -report >"${WORK}/log" 2>&1 || true
}

counts() {
    grep -Eo 'Proved goals:[[:space:]]+[0-9]+ / [0-9]+' "${WORK}/log" | tail -n 1 |
        awk '{print $(NF-2), $NF}'
}

unproved() {
    grep -E '^\[wp\] \[(Timeout|Unknown|Failed|Failure)\]' "${WORK}/log" | awk '{print $3}'
}

cp "${MODEL}" "${WORK}/model.c"

echo "=== WP proof: every function in the model ==="
wp model.c -wp-timeout 120
cat "${WORK}/log"
read -r proved total < <(counts)
if [[ -z "${total:-}" || "${proved}" != "${total}" ]]; then
    echo "Frama-C/WP left proof obligations open: ${proved:-?}/${total:-?}" >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*[0-9]+ To be validated' "${WORK}/log"; then
    echo "Frama-C/WP proved its goals, but some properties were only assumed" >&2
    exit 1
fi
echo "Frama-C/WP discharged every proof obligation: ${proved}/${total}, none assumed"

echo
echo "=== WP negative controls (each must fail) ==="
must_fail() {
    local name="$1"
    shift
    wp "$@"
    read -r proved total < <(counts)
    if [[ -z "${total:-}" || "${proved}" == "${total}" ]]; then
        echo "negative control unexpectedly proved: ${name}" >&2
        exit 1
    fi
    echo "fails as it must: ${name} (${proved}/${total}; open: $(unproved | tr '\n' ' '))"
}

for k in 1 2 3 4 5 6 7 8; do
    awk -v k="${k}" '
        /if \(checkpoint\(/ {
            if (++c == k) {
                sub(/if \(checkpoint\(/, "(void) (checkpoint(")
                sub(/\)\) return;/, "));")
            }
        }
        { print }' "${MODEL}" >"${WORK}/omit${k}.c"
    if cmp -s "${MODEL}" "${WORK}/omit${k}.c"; then
        echo "could not remove checkpoint ${k}" >&2
        exit 1
    fi
    must_fail "checkpoint ${k} ignored" "omit${k}.c"
done

sed 's|^    ++w.gen;$|    /* no bump */|' "${MODEL}" >"${WORK}/nobump.c"
if cmp -s "${MODEL}" "${WORK}/nobump.c"; then
    echo "could not remove the bump" >&2
    exit 1
fi
must_fail "install_form() does not bump the counter" nobump.c

must_fail "identity guard without its no-reinstall promise" \
    model.c -cpp-extra-args=-DIDENTITY_ALLOW_REINSTALL
if [[ "$(unproved)" != "typed_identity_checkpoint_assert" ]]; then
    echo "identity control: expected only typed_identity_checkpoint_assert open" >&2
    exit 1
fi
echo "all WP negative controls fail as they must"
