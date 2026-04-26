#!/usr/bin/env bash
# images/result-normalizers/run-result-normalizers.sh
# Converts raw tool outputs into SPT tool-result JSON.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${NORMALIZER_INPUT:=/artifacts/results}"
: "${NORMALIZER_FORMAT:=auto}"
: "${NORMALIZER_OUTPUT:=}"
: "${NORMALIZER_SARIF_OUTPUT:=}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/result-normalizers"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

log_info "Normalizing raw tool results"
log_info "  Input  : ${NORMALIZER_INPUT}"
log_info "  Format : ${NORMALIZER_FORMAT}"

ARGS=(
    --input "${NORMALIZER_INPUT}"
    --format "${NORMALIZER_FORMAT}"
    --summary-out "${RAW_DIR}/normalization-summary.json"
    --aggregate-out "${RESULTS_DIR}/tool-result.json"
)
if [[ -n "${NORMALIZER_OUTPUT}" ]]; then
    ARGS+=(--output "${NORMALIZER_OUTPUT}")
fi
if [[ -n "${NORMALIZER_SARIF_OUTPUT}" ]]; then
    ARGS+=(--sarif-out "${NORMALIZER_SARIF_OUTPUT}")
else
    ARGS+=(--sarif-out "${RESULTS_DIR}/normalized/result-normalizers.sarif")
fi

set +e
python3 /usr/local/lib/spt/result-normalizers.py "${ARGS[@]}" \
    2>&1 | tee "${ARTIFACTS_DIR}/logs/result-normalizers.log"
NORMALIZER_EXIT=${PIPESTATUS[0]}
set -e

if [[ "${NORMALIZER_EXIT}" -ne 0 ]]; then
    STATUS=failure
    log_warn "Result normalization failed"
fi

NORMALIZED_COUNT=$(jq '.normalized_count // 0' "${RAW_DIR}/normalization-summary.json" 2>/dev/null || echo 0)
FINDING_COUNT=$(jq '.finding_count // 0' "${RAW_DIR}/normalization-summary.json" 2>/dev/null || echo 0)
ERROR_COUNT=$(jq '.error_count // 0' "${RAW_DIR}/normalization-summary.json" 2>/dev/null || echo 0)

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool result-normalizers \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "normalized_count=${NORMALIZED_COUNT}" \
    --extra "finding_count=${FINDING_COUNT}" \
    --extra "error_count=${ERROR_COUNT}"

log_info "Result normalization finished (${STATUS}) in ${DURATION}s"
