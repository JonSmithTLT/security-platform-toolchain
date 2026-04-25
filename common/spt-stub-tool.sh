#!/usr/bin/env bash
# common/spt-stub-tool.sh
# Placeholder runner for planned SPT images that are wired into the bundle.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${SPT_TOOL:?SPT_TOOL must be set for stub images}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/${SPT_TOOL}"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)

log_info "${SPT_TOOL} is wired as a placeholder image"

cat > "${RAW_DIR}/stub.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "${SPT_TOOL}",
  "status": "stub",
  "message": "This image is included in the offline bundle as a planned tool placeholder."
}
JSON

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "${SPT_TOOL}",
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
    --tool "${SPT_TOOL}" \
    --status success \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "stub=true"

emit-artifact-manifest --artifacts-dir "${ARTIFACTS_DIR}" --job-id "${JOB_ID:-unknown}" >/dev/null

log_info "${SPT_TOOL} placeholder finished"
