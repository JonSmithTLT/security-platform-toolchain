#!/usr/bin/env bash
# images/ghidra-mcp/run-ghidra-mcp.sh
# Emits environment metadata for local Ghidra/MCP workflows.

set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${GHIDRA_HOME:=/opt/ghidra}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/ghidra-mcp"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

"${GHIDRA_HOME}/support/analyzeHeadless" 2>&1 | head -40 > "${RAW_DIR}/analyzeHeadless-help.txt" || true

cat > "${RAW_DIR}/environment.json" <<JSON
{
  "ghidra_home": "${GHIDRA_HOME}",
  "mode": "local-re-environment",
  "mcp_server": "not bundled"
}
JSON

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "ghidra-mcp",
  "target": "${GHIDRA_HOME}",
  "summary": {"total": 0, "critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0},
  "findings": []
}
JSON

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool ghidra-mcp \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}"
