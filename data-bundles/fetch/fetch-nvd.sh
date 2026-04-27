#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/nvd"
BASE_URL="${NVD_FEED_BASE_URL:-https://nvd.nist.gov/feeds/json/cve/2.0}"
API_URL="${NVD_API_URL:-https://services.nvd.nist.gov/rest/json/cves/2.0}"
YEARS="${NVD_YEARS:-modified recent}"
NVD_INCREMENTAL="${NVD_INCREMENTAL:-0}"

require_cmd curl
require_cmd sha256sum
require_cmd python3
mkdir -p "${OUT_DIR}"

if is_data_current "${OUT_DIR}"; then
    log "NVD CVE data is current; skipping fetch (FORCE_FETCH=1 to override)"
    exit 0
fi

if [[ "${NVD_INCREMENTAL}" == "1" ]]; then
    last_start="${NVD_LAST_MOD_START_DATE:-}"
    if [[ -z "${last_start}" && -f "${OUT_DIR}/metadata.json" ]]; then
        last_start="$(python3 - "${OUT_DIR}/metadata.json" <<'PY'
import json
import sys

metadata = json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(metadata.get("fetched_at", ""))
PY
)"
    fi

    if [[ -z "${last_start}" || "${last_start}" == "unknown" ]]; then
        warn "NVD incremental requested but no last successful fetch timestamp exists; falling back to feed fetch"
        NVD_INCREMENTAL=0
    else
        last_end="${NVD_LAST_MOD_END_DATE:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}"
        stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
        incremental_out="${OUT_DIR}/nvd-incremental-${stamp}.json"
        tmp_out="${incremental_out}.tmp"
        : > "${tmp_out}"

        log "Fetching incremental NVD CVEs from ${last_start} to ${last_end}"
        start_index=0
        results_per_page="${NVD_RESULTS_PER_PAGE:-2000}"
        total_results=1
        curl_args=(
            -fsSL
            --retry "${FETCH_CURL_RETRIES:-3}"
            --retry-delay "${FETCH_CURL_RETRY_DELAY:-2}"
            --connect-timeout "${FETCH_CURL_CONNECT_TIMEOUT:-30}"
            --max-time "${FETCH_CURL_MAX_TIME:-900}"
        )
        if [[ -n "${NVD_API_KEY:-}" ]]; then
            curl_args+=(-H "apiKey: ${NVD_API_KEY}")
        fi

        while (( start_index < total_results )); do
            page_url="$(python3 - "${API_URL}" "${last_start}" "${last_end}" "${start_index}" "${results_per_page}" <<'PY'
import sys
from urllib.parse import urlencode

base, start, end, start_index, results_per_page = sys.argv[1:6]
query = urlencode({
    "lastModStartDate": start,
    "lastModEndDate": end,
    "startIndex": start_index,
    "resultsPerPage": results_per_page,
})
print(f"{base}?{query}")
PY
)"
            page_file="${OUT_DIR}/nvd-incremental-${stamp}-${start_index}.json"
            log "Fetching NVD incremental page startIndex=${start_index} resultsPerPage=${results_per_page}"
            curl "${curl_args[@]}" "${page_url}" -o "${page_file}"
            cat "${page_file}" >> "${tmp_out}"
            printf '\n' >> "${tmp_out}"
            total_results="$(python3 - "${page_file}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(int(data.get("totalResults", 0)))
PY
)"
            start_index=$((start_index + results_per_page))
        done

        mv "${tmp_out}" "${incremental_out}"
        write_metadata "${OUT_DIR}" "nvd" "${API_URL}"
    fi
fi

if [[ "${NVD_INCREMENTAL}" != "1" ]]; then
    log "Fetching NVD CVE feeds: ${YEARS}"
    for year in ${YEARS}; do
        download "${BASE_URL}/nvdcve-2.0-${year}.json.gz" "${OUT_DIR}/nvdcve-2.0-${year}.json.gz"
        download "${BASE_URL}/nvdcve-2.0-${year}.meta" "${OUT_DIR}/nvdcve-2.0-${year}.meta"
    done
    write_metadata "${OUT_DIR}" "nvd" "${BASE_URL}"
fi

write_checksums "${OUT_DIR}"
