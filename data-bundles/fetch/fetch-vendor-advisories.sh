#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/vendor-advisories"
URLS="${VENDOR_ADVISORY_URLS:-}"

require_cmd sha256sum
mkdir -p "${OUT_DIR}"
if [[ -z "${URLS}" ]]; then
    warn "VENDOR_ADVISORY_URLS is not set; leaving ${OUT_DIR} for manually staged advisories"
    write_metadata "${OUT_DIR}" "vendor-advisories" "manual"
    exit 0
fi
require_cmd curl
log "Fetching vendor advisories"
index=0
for url in ${URLS}; do
    index=$((index + 1))
    download "${url}" "${OUT_DIR}/advisory-${index}"
done
write_metadata "${OUT_DIR}" "vendor-advisories" "VENDOR_ADVISORY_URLS"
write_checksums "${OUT_DIR}"
