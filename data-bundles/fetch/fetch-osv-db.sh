#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/osv"
MODE="${OSV_FETCH_MODE:-direct}"
ECOSYSTEMS="${OSV_ECOSYSTEMS:-}"
OSV_BUCKET="${OSV_BUCKET_URL:-https://osv-vulnerabilities.storage.googleapis.com}"

require_cmd sha256sum
mkdir -p "${OUT_DIR}"

if [[ "${MODE}" == "scanner" ]]; then
    if ! command -v osv-scanner >/dev/null 2>&1; then
        warn "osv-scanner is not installed on the connected host; falling back to direct OSV DB download"
        MODE=direct
    else
        log "Fetching OSV offline vulnerability databases with osv-scanner"
        OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY="${OUT_DIR}" osv-scanner \
            --download-offline-databases \
            --offline-vulnerabilities \
            .
        write_metadata "${OUT_DIR}" "osv" "osv-scanner --download-offline-databases"
        write_checksums "${OUT_DIR}"
        exit 0
    fi
fi

require_cmd curl
require_cmd python3

log "Fetching OSV offline vulnerability databases directly from ${OSV_BUCKET}"
if [[ -z "${ECOSYSTEMS}" ]]; then
    download "${OSV_BUCKET}/ecosystems.txt" "${OUT_DIR}/ecosystems.txt"
    ECOSYSTEM_FILE="${OUT_DIR}/ecosystems.txt"
else
    ECOSYSTEM_FILE="${OUT_DIR}/ecosystems.selected.txt"
    printf '%s\n' "${ECOSYSTEMS}" | tr ',' '\n' > "${ECOSYSTEM_FILE}"
fi

while IFS= read -r ecosystem; do
    [[ -z "${ecosystem}" ]] && continue
    encoded="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "${ecosystem}")"
    dest="${OUT_DIR}/osv-scanner/${ecosystem}/all.zip"
    if ! download "${OSV_BUCKET}/${encoded}/all.zip" "${dest}"; then
        warn "Could not fetch OSV ecosystem database: ${ecosystem}"
        rm -f "${dest}"
    fi
done < "${ECOSYSTEM_FILE}"

if ! find "${OUT_DIR}/osv-scanner" -name all.zip -type f 2>/dev/null | grep -q .; then
    warn "No OSV ecosystem databases were downloaded"
    mkdir -p "${OUT_DIR}"
else
    count="$(find "${OUT_DIR}/osv-scanner" -name all.zip -type f | wc -l | tr -d ' ')"
    log "Fetched ${count} OSV ecosystem databases"
fi
write_metadata "${OUT_DIR}" "osv" "${OSV_BUCKET}"
write_checksums "${OUT_DIR}"
