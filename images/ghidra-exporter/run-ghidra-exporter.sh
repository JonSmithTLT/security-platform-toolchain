#!/usr/bin/env bash
# images/ghidra-exporter/run-ghidra-exporter.sh
# Runs Ghidra headless analysis against one binary.

set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${GHIDRA_HOME:=/opt/ghidra}"
: "${GHIDRA_TARGET:=/workspace}"
: "${GHIDRA_PROJECT:=/tmp/ghidra-project}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/ghidra-exporter"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs" "${GHIDRA_PROJECT}"

START_TIME=$(date +%s)
STATUS=success
TARGET_FILE="${GHIDRA_TARGET}"
if [[ -d "${TARGET_FILE}" ]]; then
    TARGET_FILE="$(find "${TARGET_FILE}" -type f -perm -111 | head -1)"
fi

if [[ -z "${TARGET_FILE}" || ! -f "${TARGET_FILE}" ]]; then
    log_warn "No executable target found"
    STATUS=failure
else
    "${GHIDRA_HOME}/support/analyzeHeadless" "${GHIDRA_PROJECT}" spt-project \
        -import "${TARGET_FILE}" \
        -analysisTimeoutPerFile 120 \
        -deleteProject \
        2>&1 | tee "${RAW_DIR}/analyzeHeadless.log" | tee "${ARTIFACTS_DIR}/logs/ghidra-exporter.log" \
        || { STATUS=failure; log_warn "Ghidra headless analysis failed"; }
fi

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "ghidra-exporter",
  "target": "${TARGET_FILE}",
  "summary": {"total": 0, "critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0},
  "findings": []
}
JSON

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool ghidra-exporter \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}"
