#!/usr/bin/env bash
# images/coverage-tools/run-coverage-tools.sh
# Collects coverage artifacts from gcov/lcov-compatible projects.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${TARGET_REPO:=/workspace}"
: "${COVERAGE_ROOT:=/workspace}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/coverage-tools"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

log_info "Collecting coverage"
log_info "  Target : ${TARGET_REPO}"
log_info "  Root   : ${COVERAGE_ROOT}"

GCDA_COUNT=$(find "${COVERAGE_ROOT}" -name '*.gcda' -type f 2>/dev/null | wc -l || echo 0)
INFO_FILE="${RAW_DIR}/coverage.info"
JSON_FILE="${RAW_DIR}/coverage.json"
XML_FILE="${RAW_DIR}/coverage.xml"

if [[ "${GCDA_COUNT}" -gt 0 ]]; then
    gcovr "${COVERAGE_ROOT}" \
        --root "${TARGET_REPO}" \
        --json "${JSON_FILE}" \
        --xml "${XML_FILE}" \
        2>&1 | tee "${ARTIFACTS_DIR}/logs/coverage-tools.log" \
        || { STATUS=failure; log_warn "gcovr exited non-zero"; }

    lcov --capture \
        --directory "${COVERAGE_ROOT}" \
        --output-file "${INFO_FILE}" \
        2>&1 | tee -a "${ARTIFACTS_DIR}/logs/coverage-tools.log" \
        || log_warn "lcov capture exited non-zero"
else
    log_warn "No .gcda files found; writing empty coverage summary"
    cat > "${JSON_FILE}" <<'JSON'
{
  "files": []
}
JSON
fi

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "coverage-tools",
  "target": "${TARGET_REPO}",
  "summary": {
    "total": 0,
    "critical": 0,
    "high": 0,
    "medium": 0,
    "low": 0,
    "info": 0
  },
  "findings": []
}
JSON

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool coverage-tools \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "gcda_count=${GCDA_COUNT}"

log_info "Coverage collection finished (${STATUS}) in ${DURATION}s"
