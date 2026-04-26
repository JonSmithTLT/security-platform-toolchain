#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${ARTIFACTS_DIR:=/artifacts}"
: "${HARNESS_ENGINE:=libfuzzer}"
: "${HARNESS_NAME:=spt_harness}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/harness-builder"
mkdir -p "${RESULTS_DIR}/raw" "${ARTIFACTS_DIR}/logs"
START_TIME=$(date +%s)
STATUS=success
EXIT_CODE=0

{
    generate-harness
    build-harness
    smoke-harness
    validate-harness
    package-harness
} 2>&1 | tee "${ARTIFACTS_DIR}/logs/harness-builder.log" || {
    STATUS=failure
    EXIT_CODE=1
}

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{"schema_version":"1.0.0","tool":"harness-builder","target":"${HARNESS_NAME}","summary":{"total":0,"critical":0,"high":0,"medium":0,"low":0,"info":0},"findings":[]}
JSON

emit-job-report --tool harness-builder --status "${STATUS}" --results-file "${RESULTS_DIR}/tool-result.json" --extra "duration_seconds=${DURATION}" --extra "engine=${HARNESS_ENGINE}" --extra "exit_code=${EXIT_CODE}"

exit "${EXIT_CODE}"
