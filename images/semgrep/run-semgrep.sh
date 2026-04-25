#!/usr/bin/env bash
# images/semgrep/run-semgrep.sh
# Runs Semgrep and converts output to the normalised tool-result schema.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${TARGET_REPO:=/workspace}"
: "${SEMGREP_RULES:=/rules}"
: "${ARTIFACTS_DIR:=/artifacts}"
: "${SEMGREP_TIMEOUT:=300}"
: "${SEMGREP_JOBS:=4}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/semgrep"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

log_info "Starting Semgrep scan"
log_info "  Target : ${TARGET_REPO}"
log_info "  Rules  : ${SEMGREP_RULES}"

semgrep \
    --config "${SEMGREP_RULES}" \
    --json \
    --metrics=off \
    --output "${RAW_DIR}/semgrep.json" \
    --timeout "${SEMGREP_TIMEOUT}" \
    --jobs "${SEMGREP_JOBS}" \
    "${TARGET_REPO}" \
    2>&1 | tee "${ARTIFACTS_DIR}/logs/semgrep.log" \
    || { STATUS=failure; log_warn "semgrep exited non-zero"; }

# ── Convert to tool-result.schema.json ────────────────────────────────────
FINDING_COUNT=0
if [[ -f "${RAW_DIR}/semgrep.json" ]]; then
    FINDING_COUNT=$(jq '.results | length' "${RAW_DIR}/semgrep.json" 2>/dev/null || echo 0)
    jq --arg tool semgrep '
    def spt_severity:
        ascii_downcase as $s |
        if $s == "error" then "high"
        elif $s == "warning" or $s == "warn" then "medium"
        elif $s == "note" then "info"
        elif $s == "critical" or $s == "high" or $s == "medium" or $s == "low" or $s == "info" then $s
        else "info"
        end;
    {
        schema_version: "1.0.0",
        tool: $tool,
        findings: [.results[] | {
            id: .check_id,
            title: .extra.message,
            severity: (.extra.severity // "info" | spt_severity),
            rule_id: .check_id,
            location: {
                file: .path,
                line_start: .start.line,
                line_end: .end.line,
                col_start: .start.col,
                col_end: .end.col,
                snippet: .extra.lines
            },
            message: .extra.message,
            raw: .
        }]
    }' "${RAW_DIR}/semgrep.json" > "${RESULTS_DIR}/tool-result.json"
fi

log_info "Findings: ${FINDING_COUNT}"

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool semgrep \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "finding_count=${FINDING_COUNT}"

log_info "Semgrep finished (${STATUS}) in ${DURATION}s"
