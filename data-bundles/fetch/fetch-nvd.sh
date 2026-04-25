#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/nvd"
BASE_URL="${NVD_FEED_BASE_URL:-https://nvd.nist.gov/feeds/json/cve/2.0}"
YEARS="${NVD_YEARS:-modified recent}"

require_cmd curl
require_cmd sha256sum
log "Fetching NVD CVE feeds: ${YEARS}"
mkdir -p "${OUT_DIR}"
for year in ${YEARS}; do
    download "${BASE_URL}/nvdcve-2.0-${year}.json.gz" "${OUT_DIR}/nvdcve-2.0-${year}.json.gz"
    download "${BASE_URL}/nvdcve-2.0-${year}.meta" "${OUT_DIR}/nvdcve-2.0-${year}.meta"
done
write_metadata "${OUT_DIR}" "nvd" "${BASE_URL}"
write_checksums "${OUT_DIR}"
