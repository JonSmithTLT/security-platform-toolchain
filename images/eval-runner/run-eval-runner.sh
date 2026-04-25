#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${EVAL_CASES:=/eval/cases.jsonl}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/eval-runner"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

python3 /usr/local/lib/spt/eval-runner.py \
    --cases "${EVAL_CASES}" \
    --results-out "${RAW_DIR}/eval-results.json" \
    2>&1 | tee "${ARTIFACTS_DIR}/logs/eval-runner.log" \
    || { STATUS=failure; log_warn "evaluations failed"; }

PASS_COUNT=$(jq '.pass_count // 0' "${RAW_DIR}/eval-results.json" 2>/dev/null || echo 0)
FAIL_COUNT=$(jq '.fail_count // 0' "${RAW_DIR}/eval-results.json" 2>/dev/null || echo 0)

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "eval-runner",
  "target": "${EVAL_CASES}",
  "summary": {"total": ${FAIL_COUNT}, "critical": 0, "high": ${FAIL_COUNT}, "medium": 0, "low": 0, "info": 0},
  "findings": []
}
JSON

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool eval-runner \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "pass_count=${PASS_COUNT}" \
    --extra "fail_count=${FAIL_COUNT}"
