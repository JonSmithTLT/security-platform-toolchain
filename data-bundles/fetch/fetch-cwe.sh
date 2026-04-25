#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/cwe"
URL="${CWE_URL:-https://cwe.mitre.org/data/xml/cwec_latest.xml.zip}"

require_cmd curl
require_cmd sha256sum
log "Fetching CWE"
download "${URL}" "${OUT_DIR}/cwec_latest.xml.zip"
write_metadata "${OUT_DIR}" "cwe" "${URL}"
write_checksums "${OUT_DIR}"
