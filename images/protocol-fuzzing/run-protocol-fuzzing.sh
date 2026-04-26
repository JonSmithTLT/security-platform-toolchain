#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${ARTIFACTS_DIR:=/artifacts}"
RESULTS_DIR="${ARTIFACTS_DIR}/results/protocol-fuzzing"
mkdir -p "${RESULTS_DIR}/raw" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success
trap 'stop-target || true' EXIT

start-target
capture-pcap || true
run-boofuzz || STATUS=failure

if [[ -f "${ARTIFACTS_DIR}/logs/tcpdump.pid" ]]; then
    kill "$(cat "${ARTIFACTS_DIR}/logs/tcpdump.pid")" 2>/dev/null || true
fi
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
FAILURES=$(DURATION_SECONDS="${DURATION}" emit-protocol-report | tail -1)

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{"schema_version":"1.0.0","tool":"protocol-fuzzing","target":"${PROTOCOL_TARGET_HOST:-127.0.0.1}:${PROTOCOL_TARGET_PORT:-9001}","summary":{"total":${FAILURES},"critical":0,"high":${FAILURES},"medium":0,"low":0,"info":0},"findings":[]}
JSON

emit-job-report --tool protocol-fuzzing --status "${STATUS}" --results-file "${RESULTS_DIR}/tool-result.json" --extra "duration_seconds=${DURATION}" --extra "failure_count=${FAILURES}"
