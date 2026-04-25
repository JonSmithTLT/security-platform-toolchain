#!/usr/bin/env bash
# images/osv-scanner/run-osv-scanner.sh
# Runs OSV Scanner. Offline mode expects a local DB cache mounted at
# OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY.

set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${TARGET_REPO:=/workspace}"
: "${OSV_OFFLINE:=1}"
: "${OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY:=/osv-db}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/osv-scanner"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success
RAW_OUT="${RAW_DIR}/osv-scanner.json"

ARGS=(scan source --recursive --format json --output-file "${RAW_OUT}" "${TARGET_REPO}")
if [[ "${OSV_OFFLINE}" == "1" || "${OSV_OFFLINE,,}" == "true" ]]; then
    if [[ ! -d "${OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY}" ]]; then
        log_error "OSV offline mode requires OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY=${OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY}"
        log_error "Prepare it on a connected machine with: OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY=<dir> osv-scanner --download-offline-databases --offline-vulnerabilities <target>"
        STATUS=failure
    else
        export OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY
        ARGS+=(--offline-vulnerabilities)
    fi
fi

log_info "Running OSV Scanner"
log_info "  Target  : ${TARGET_REPO}"
log_info "  Offline : ${OSV_OFFLINE}"
log_info "  DB cache: ${OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY}"
log_info "  Native  : ${ARGS[*]}"

if [[ "${STATUS}" == "success" ]]; then
    osv-scanner "${ARGS[@]}" \
        2>&1 | tee "${ARTIFACTS_DIR}/logs/osv-scanner.log" \
        || { STATUS=failure; log_warn "osv-scanner exited non-zero"; }
else
    : > "${ARTIFACTS_DIR}/logs/osv-scanner.log"
fi

if [[ ! -f "${RAW_OUT}" ]]; then
    echo '{"results":[]}' > "${RAW_OUT}"
fi

VULN_COUNT=$(jq '[.results[]?.packages[]?.vulnerabilities[]?] | length' "${RAW_OUT}" 2>/dev/null || echo 0)

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "osv-scanner",
  "target": "${TARGET_REPO}",
  "summary": {"total": ${VULN_COUNT}, "critical": 0, "high": ${VULN_COUNT}, "medium": 0, "low": 0, "info": 0},
  "findings": []
}
JSON

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool osv-scanner \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "vulnerability_count=${VULN_COUNT}" \
    --extra "offline=${OSV_OFFLINE}" \
    --extra "offline_db_cache=${OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY}"
