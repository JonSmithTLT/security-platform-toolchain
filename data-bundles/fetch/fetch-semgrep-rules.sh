#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/semgrep-rules"
URL="${SEMGREP_RULES_REPO_URL:-}"

require_cmd sha256sum
mkdir -p "${OUT_DIR}"
if [[ -z "${URL}" ]]; then
    warn "SEMGREP_RULES_REPO_URL is not set; copying repo-local starter rules"
    mkdir -p "${OUT_DIR}/local"
    cp -R rules/semgrep/. "${OUT_DIR}/local/"
    write_metadata "${OUT_DIR}" "semgrep-rules" "repo-local"
    write_checksums "${OUT_DIR}"
    exit 0
fi
require_cmd git
log "Fetching Semgrep rules from ${URL}"
if [[ -d "${OUT_DIR}/.git" ]]; then
    git -C "${OUT_DIR}" pull --ff-only
else
    rm -rf "${OUT_DIR}"
    git clone --depth 1 "${URL}" "${OUT_DIR}"
fi
write_metadata "${OUT_DIR}" "semgrep-rules" "${URL}"
write_checksums "${OUT_DIR}"
