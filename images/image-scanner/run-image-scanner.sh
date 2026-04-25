#!/usr/bin/env bash
# images/image-scanner/run-image-scanner.sh
# Runs Grype against a filesystem path, SBOM, or image reference.

set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${IMAGE_SCAN_TARGET:=/workspace}"
: "${ARTIFACTS_DIR:=/artifacts}"
: "${GRYPE_DB_AUTO_UPDATE:=false}"
: "${GRYPE_CHECK_FOR_APP_UPDATE:=false}"

export GRYPE_DB_AUTO_UPDATE
export GRYPE_CHECK_FOR_APP_UPDATE

RESULTS_DIR="${ARTIFACTS_DIR}/results/image-scanner"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success
RAW_OUT="${RAW_DIR}/grype.json"

log_info "Running Grype"
log_info "  Target : ${IMAGE_SCAN_TARGET}"
log_info "  Offline: GRYPE_DB_AUTO_UPDATE=${GRYPE_DB_AUTO_UPDATE}, GRYPE_CHECK_FOR_APP_UPDATE=${GRYPE_CHECK_FOR_APP_UPDATE}"

grype "${IMAGE_SCAN_TARGET}" \
    -o json \
    --file "${RAW_OUT}" \
    2>&1 | tee "${ARTIFACTS_DIR}/logs/image-scanner.log" \
    || { STATUS=failure; log_warn "grype exited non-zero"; }

if [[ ! -f "${RAW_OUT}" ]]; then
    echo '{"matches":[]}' > "${RAW_OUT}"
fi

FINDING_COUNT=$(jq '.matches | length' "${RAW_OUT}" 2>/dev/null || echo 0)

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "image-scanner",
  "target": "${IMAGE_SCAN_TARGET}",
  "summary": {"total": ${FINDING_COUNT}, "critical": 0, "high": ${FINDING_COUNT}, "medium": 0, "low": 0, "info": 0},
  "findings": []
}
JSON

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool image-scanner \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "finding_count=${FINDING_COUNT}"
