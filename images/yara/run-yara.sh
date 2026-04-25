#!/usr/bin/env bash
# images/yara/run-yara.sh
# Runs YARA rules against a mounted target directory.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${YARA_RULES:=/rules}"
: "${YARA_TARGET:=/workspace}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/yara"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success
RAW_OUT="${RAW_DIR}/yara.txt"

log_info "Running YARA"
log_info "  Rules  : ${YARA_RULES}"
log_info "  Target : ${YARA_TARGET}"

if [[ ! -d "${YARA_RULES}" ]] || ! find "${YARA_RULES}" \( -name '*.yar' -o -name '*.yara' \) -type f | grep -q .; then
    log_warn "No YARA rules found; writing empty result"
    : > "${RAW_OUT}"
else
    yara -r "${YARA_RULES}" "${YARA_TARGET}" \
        2>&1 | tee "${RAW_OUT}" | tee "${ARTIFACTS_DIR}/logs/yara.log" \
        || { STATUS=failure; log_warn "yara exited non-zero"; }
fi

FINDING_COUNT=$(grep -cve '^[[:space:]]*$' "${RAW_OUT}" 2>/dev/null || echo 0)

jq -Rn --arg tool yara --arg target "${YARA_TARGET}" '
  [inputs | select(length > 0)] as $lines |
  {
    schema_version: "1.0.0",
    tool: $tool,
    target: $target,
    summary: {total: ($lines|length), critical: 0, high: 0, medium: ($lines|length), low: 0, info: 0},
    findings: [
      $lines[] as $line |
      {
        id: ($line | @base64),
        title: "YARA rule matched",
        severity: "medium",
        rule_id: ($line | split(" ")[0]),
        message: $line,
        raw: {line: $line}
      }
    ]
  }' "${RAW_OUT}" > "${RESULTS_DIR}/tool-result.json"

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool yara \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "finding_count=${FINDING_COUNT}"

log_info "YARA finished (${STATUS}) in ${DURATION}s"
