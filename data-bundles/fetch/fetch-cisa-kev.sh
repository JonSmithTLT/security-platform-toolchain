#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=data-bundles/fetch/fetch-lib.sh
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/cisa-kev"
URL="${CISA_KEV_URL:-https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json}"

require_cmd curl
require_cmd sha256sum
log "Fetching CISA KEV"
download "${URL}" "${OUT_DIR}/known_exploited_vulnerabilities.json"
write_metadata "${OUT_DIR}" "cisa-kev" "${URL}"
write_checksums "${OUT_DIR}"
