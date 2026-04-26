#!/usr/bin/env bash
set -euo pipefail

: "${ARTIFACTS_DIR:=/artifacts}"
RESULTS_DIR="${ARTIFACTS_DIR}/results/crash-triage"
CRASH_TYPE="$(jq -r '.crash_type' "${RESULTS_DIR}/normalized/crash-triage.json")"
cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{"schema_version":"1.0.0","tool":"crash-triage","target":"${CRASH_LOG:-/workspace/asan.log}","summary":{"total":1,"critical":0,"high":1,"medium":0,"low":0,"info":0},"findings":[{"id":"crash-triage-1","title":"Crash triaged","severity":"high","message":"${CRASH_TYPE}"}]}
JSON
