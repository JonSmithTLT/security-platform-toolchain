#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/epss"
URL="${EPSS_URL:-https://epss.cyentia.com/epss_scores-current.csv.gz}"

require_cmd curl
require_cmd sha256sum
if is_data_current "${OUT_DIR}"; then
    log "EPSS data is current; skipping fetch (FORCE_FETCH=1 to override)"
    exit 0
fi
log "Fetching EPSS current scores"
download "${URL}" "${OUT_DIR}/epss_scores-current.csv.gz"
write_metadata "${OUT_DIR}" "epss" "${URL}"
write_checksums "${OUT_DIR}"
