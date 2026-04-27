#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/github-advisory-db"
URL="${GHSA_REPO_URL:-https://github.com/github/advisory-database.git}"
REF="${GHSA_REF:-main}"
CACHE_KEY="$(dataset_cache_key "github-advisory-db" "${URL}" "${REF}")"

require_cmd git
require_cmd sha256sum
log "Fetching GitHub Advisory Database"
if restore_dataset_cache "github-advisory-db" "${CACHE_KEY}" "${OUT_DIR}"; then
    exit 0
fi

if [[ -d "${OUT_DIR}/.git" ]]; then
    git -C "${OUT_DIR}" fetch --depth 1 origin "${REF}"
    git -C "${OUT_DIR}" checkout -q FETCH_HEAD
else
    rm -rf "${OUT_DIR}"
    git clone --depth 1 --branch "${REF}" "${URL}" "${OUT_DIR}"
fi
write_metadata "${OUT_DIR}" "github-advisory-db" "${URL}"
write_checksums "${OUT_DIR}"
store_dataset_cache "github-advisory-db" "${CACHE_KEY}" "${OUT_DIR}"
