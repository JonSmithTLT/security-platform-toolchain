#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/osv"

require_cmd sha256sum
if ! command -v osv-scanner >/dev/null 2>&1; then
    warn "osv-scanner is not installed on the connected host; skipping OSV offline DB download"
    warn "Install or run spt-osv-scanner and execute: osv-scanner --download-offline-databases --offline-vulnerabilities --local-db-cache-directory ${OUT_DIR}"
    mkdir -p "${OUT_DIR}"
    write_metadata "${OUT_DIR}" "osv" "osv-scanner --download-offline-databases"
    exit 0
fi

log "Fetching OSV offline vulnerability databases"
mkdir -p "${OUT_DIR}"
osv-scanner \
    --download-offline-databases \
    --offline-vulnerabilities \
    --local-db-cache-directory "${OUT_DIR}"
write_metadata "${OUT_DIR}" "osv" "osv-scanner --download-offline-databases"
write_checksums "${OUT_DIR}"
