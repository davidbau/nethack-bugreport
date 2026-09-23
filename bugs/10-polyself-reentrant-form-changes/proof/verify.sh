#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

node "${SCRIPT_DIR}/audit-form-transitions.mjs"
node "${SCRIPT_DIR}/audit-callgraph.mjs"
bash "${SCRIPT_DIR}/run-cbmc.sh"
bash "${SCRIPT_DIR}/run-wp.sh"
