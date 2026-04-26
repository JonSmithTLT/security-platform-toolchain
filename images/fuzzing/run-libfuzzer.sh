#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${FUZZ_TARGET:?FUZZ_TARGET must be set}"
: "${FUZZ_TIMEOUT:=300}"
: "${FUZZ_CORPUS:=/workspace/corpus}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/fuzzing"
RAW_DIR="${RESULTS_DIR}/raw"
EVIDENCE_DIR="${RESULTS_DIR}/evidence"
NORM_DIR="${RESULTS_DIR}/normalized"
REPORT_DIR="${RESULTS_DIR}/reports"
mkdir -p "${RAW_DIR}/libfuzzer-out" "${EVIDENCE_DIR}/crashes" "${EVIDENCE_DIR}/seeds" "${NORM_DIR}" "${REPORT_DIR}" "${ARTIFACTS_DIR}/logs" "${FUZZ_CORPUS}"

START_TIME=$(date +%s)
STATUS=success
if [[ -z "$(ls -A "${FUZZ_CORPUS}" 2>/dev/null)" ]]; then
    echo "A" > "${FUZZ_CORPUS}/seed0"
fi

log_info "Starting libFuzzer run"
set +e
ASAN_OPTIONS="${SPT_ASAN_OPTIONS_SYMBOLIZED:-abort_on_error=1:symbolize=1:detect_leaks=0}" \
    timeout "${FUZZ_TIMEOUT}" "${FUZZ_TARGET}" "${FUZZ_CORPUS}" \
    -artifact_prefix="${RAW_DIR}/libfuzzer-out/" \
    -max_total_time="${FUZZ_TIMEOUT}" \
    -print_final_stats=1 \
    2>&1 | tee "${ARTIFACTS_DIR}/logs/fuzzing.log"
EXIT_CODE=${PIPESTATUS[0]}
set -e
if [[ "${EXIT_CODE}" -ne 0 && "${EXIT_CODE}" -ne 124 ]]; then
    STATUS=failure
fi

CRASH_COUNT=$(collect-crashes libfuzzer "${FUZZ_TARGET}" "${RAW_DIR}" "${EVIDENCE_DIR}/crashes" "${NORM_DIR}/crashes.json" | tail -1)
HANG_COUNT=0
if [[ -d "${RAW_DIR}/libfuzzer-out" ]]; then
    HANG_COUNT=$(find "${RAW_DIR}/libfuzzer-out" -type f -name 'timeout-*' | wc -l | tr -d ' ')
fi
EXEC_COUNT=$(grep -Eo 'stat::number_of_executed_units: [0-9]+' "${ARTIFACTS_DIR}/logs/fuzzing.log" | awk '{print $2}' | tail -1)
EXEC_COUNT="${EXEC_COUNT:-0}"
TARGET_SHA=$(sha256sum "${FUZZ_TARGET}" | awk '{print $1}')
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

cat > "${NORM_DIR}/fuzz-campaign.json" <<JSON
{
  "schema_version": "1.0.0",
  "engine": "libfuzzer",
  "target": "${FUZZ_TARGET}",
  "target_sha256": "${TARGET_SHA}",
  "instrumentation": "clang -fsanitize=fuzzer",
  "sanitizers": ["address", "undefined"],
  "duration_seconds": ${DURATION},
  "exec_count": ${EXEC_COUNT},
  "crash_count": ${CRASH_COUNT},
  "hang_count": ${HANG_COUNT},
  "corpus_in": "${FUZZ_CORPUS}",
  "corpus_out": "${FUZZ_CORPUS}"
}
JSON

cat > "${REPORT_DIR}/fuzz-summary.md" <<EOF
# Fuzz Summary

- Engine: libFuzzer
- Target: ${FUZZ_TARGET}
- Duration: ${DURATION}s
- Executions: ${EXEC_COUNT}
- Crashes: ${CRASH_COUNT}
- Hangs: ${HANG_COUNT}
EOF

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{"schema_version":"1.0.0","tool":"fuzzing","target":"${FUZZ_TARGET}","summary":{"total":${CRASH_COUNT},"critical":0,"high":${CRASH_COUNT},"medium":0,"low":0,"info":0},"findings":[]}
JSON

emit-job-report --tool fuzzing --status "${STATUS}" --results-file "${RESULTS_DIR}/tool-result.json" --extra "duration_seconds=${DURATION}" --extra "engine=libfuzzer" --extra "crash_count=${CRASH_COUNT}" --extra "hang_count=${HANG_COUNT}"
