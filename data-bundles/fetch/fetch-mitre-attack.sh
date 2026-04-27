#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/mitre-attack"
BASE_URL="${MITRE_ATTACK_BASE_URL:-https://raw.githubusercontent.com/mitre-attack/attack-stix-data/master}"

require_cmd curl
require_cmd sha256sum
if is_data_current "${OUT_DIR}"; then
    log "MITRE ATT&CK data is current; skipping fetch (FORCE_FETCH=1 to override)"
    exit 0
fi
log "Fetching MITRE ATT&CK STIX data"
download "${BASE_URL}/enterprise-attack/enterprise-attack.json" "${OUT_DIR}/enterprise-attack.json"
download "${BASE_URL}/mobile-attack/mobile-attack.json" "${OUT_DIR}/mobile-attack.json"
download "${BASE_URL}/ics-attack/ics-attack.json" "${OUT_DIR}/ics-attack.json"
write_metadata "${OUT_DIR}" "mitre-attack" "${BASE_URL}"
write_checksums "${OUT_DIR}"
