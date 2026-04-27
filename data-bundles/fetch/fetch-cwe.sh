#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/cwe"
URL="${CWE_URL:-https://cwe.mitre.org/data/xml/cwec_latest.xml.zip}"

require_cmd curl
require_cmd sha256sum
if is_data_current "${OUT_DIR}"; then
    log "CWE data is current; skipping fetch (FORCE_FETCH=1 to override)"
    exit 0
fi
log "Fetching CWE"
download "${URL}" "${OUT_DIR}/cwec_latest.xml.zip"
write_metadata "${OUT_DIR}" "cwe" "${URL}"
write_checksums "${OUT_DIR}"
