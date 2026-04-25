#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/capec"
URL="${CAPEC_URL:-https://capec.mitre.org/data/xml/capec_latest.xml}"

require_cmd curl
require_cmd sha256sum
log "Fetching CAPEC"
download "${URL}" "${OUT_DIR}/capec_latest.xml"
write_metadata "${OUT_DIR}" "capec" "${URL}"
write_checksums "${OUT_DIR}"
