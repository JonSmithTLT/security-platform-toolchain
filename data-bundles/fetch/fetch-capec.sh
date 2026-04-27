#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/capec"
URL="${CAPEC_URL:-https://capec.mitre.org/data/xml/capec_latest.xml}"

require_cmd curl
require_cmd sha256sum
if is_data_current "${OUT_DIR}"; then
    log "CAPEC data is current; skipping fetch (FORCE_FETCH=1 to override)"
    exit 0
fi
log "Fetching CAPEC"
download "${URL}" "${OUT_DIR}/capec_latest.xml"
write_metadata "${OUT_DIR}" "capec" "${URL}"
write_checksums "${OUT_DIR}"
