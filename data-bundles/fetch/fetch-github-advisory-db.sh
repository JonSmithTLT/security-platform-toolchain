#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/github-advisory-db"
URL="${GHSA_REPO_URL:-https://github.com/github/advisory-database.git}"

require_cmd git
require_cmd sha256sum
log "Fetching GitHub Advisory Database"
if [[ -d "${OUT_DIR}/.git" ]]; then
    git -C "${OUT_DIR}" fetch --depth 1 origin main
    git -C "${OUT_DIR}" checkout -q FETCH_HEAD
else
    rm -rf "${OUT_DIR}"
    git clone --depth 1 "${URL}" "${OUT_DIR}"
fi
write_metadata "${OUT_DIR}" "github-advisory-db" "${URL}"
write_checksums "${OUT_DIR}"
