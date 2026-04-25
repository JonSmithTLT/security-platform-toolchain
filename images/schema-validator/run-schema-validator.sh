#!/usr/bin/env bash
# images/schema-validator/run-schema-validator.sh
# Validates SPT artifacts and emits a normalised validation result.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${VALIDATE_TARGET:=/artifacts}"
: "${SCHEMAS_DIR:=/usr/local/share/spt/schemas}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/schema-validator"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

log_info "Validating artifacts"
log_info "  Target  : ${VALIDATE_TARGET}"
log_info "  Schemas : ${SCHEMAS_DIR}"

set +e
python3 /usr/local/lib/spt/schema-validator.py \
    --target "${VALIDATE_TARGET}" \
    --schemas-dir "${SCHEMAS_DIR}" \
    --summary-out "${RAW_DIR}/validation-summary.json" \
    --tool-result-out "${RESULTS_DIR}/tool-result.json" \
    2>&1 | tee "${ARTIFACTS_DIR}/logs/schema-validator.log"
VALIDATION_EXIT=${PIPESTATUS[0]}
set -e

if [[ "${VALIDATION_EXIT}" -ne 0 ]]; then
    STATUS=failure
    log_warn "Schema validation found errors"
fi

ERROR_COUNT=$(jq '.error_count // 0' "${RAW_DIR}/validation-summary.json" 2>/dev/null || echo 0)
VALIDATED_COUNT=$(jq '.validated_count // 0' "${RAW_DIR}/validation-summary.json" 2>/dev/null || echo 0)

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool schema-validator \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "validated_count=${VALIDATED_COUNT}" \
    --extra "error_count=${ERROR_COUNT}"

log_info "Schema validation finished (${STATUS}) in ${DURATION}s"
