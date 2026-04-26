#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${ARTIFACTS_DIR:=/artifacts}"
START_TIME=$(date +%s)
STATUS=success

triage-crash 2>&1 | tee "${ARTIFACTS_DIR}/logs/crash-triage.log" || STATUS=failure
reproduce-crash || true
emit-triage-report

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
emit-job-report --tool crash-triage --status "${STATUS}" --results-file "${ARTIFACTS_DIR}/results/crash-triage/tool-result.json" --extra "duration_seconds=${DURATION}"
