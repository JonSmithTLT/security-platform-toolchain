#!/usr/bin/env bash
# images/codeql/run-codeql.sh
# Creates a CodeQL database and runs security queries against it.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${TARGET_REPO:=/workspace}"
: "${CODEQL_LANGUAGE:=cpp}"
: "${CODEQL_QUERIES:=/queries}"
: "${CODEQL_DB:=/tmp/codeql-db}"
: "${ARTIFACTS_DIR:=/artifacts}"
: "${CODEQL_BUILD_CMD:=}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/codeql"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

log_info "Starting CodeQL analysis"
log_info "  Language : ${CODEQL_LANGUAGE}"
log_info "  Target   : ${TARGET_REPO}"

# ── Create database ────────────────────────────────────────────────────────
log_info "Creating CodeQL database at ${CODEQL_DB}"
DB_ARGS=(database create "${CODEQL_DB}"
    --language="${CODEQL_LANGUAGE}"
    --source-root="${TARGET_REPO}"
    --overwrite)
[[ -n "${CODEQL_BUILD_CMD}" ]] && DB_ARGS+=(--command="${CODEQL_BUILD_CMD}")
codeql "${DB_ARGS[@]}" 2>&1 | tee "${ARTIFACTS_DIR}/logs/codeql.log" \
    || { STATUS=failure; log_error "Database creation failed"; }

# ── Run queries ────────────────────────────────────────────────────────────
SARIF_OUT="${RAW_DIR}/codeql.sarif"
if [[ "${STATUS}" == "success" ]]; then
    log_info "Running queries from ${CODEQL_QUERIES}"
    codeql database analyze "${CODEQL_DB}" \
        "${CODEQL_QUERIES}" \
        --format=sarif-latest \
        --output="${SARIF_OUT}" \
        2>&1 | tee -a "${ARTIFACTS_DIR}/logs/codeql.log" \
        || { STATUS=failure; log_warn "Query execution failed"; }
fi

# ── Count findings ─────────────────────────────────────────────────────────
FINDING_COUNT=0
if [[ -f "${SARIF_OUT}" ]]; then
    FINDING_COUNT=$(jq '[.runs[].results[]] | length' "${SARIF_OUT}" 2>/dev/null || echo 0)
fi
log_info "Findings: ${FINDING_COUNT}"

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool codeql \
    --status "${STATUS}" \
    --extra "duration_seconds=${DURATION}" \
    --extra "finding_count=${FINDING_COUNT}"

log_info "CodeQL finished (${STATUS}) in ${DURATION}s"
