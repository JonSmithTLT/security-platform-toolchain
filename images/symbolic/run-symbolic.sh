#!/usr/bin/env bash
# images/symbolic/run-symbolic.sh
# Dispatch to the selected symbolic execution engine.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${SYMBOLIC_ENGINE:=angr}"
: "${TARGET_BINARY:?TARGET_BINARY must be set to the path of the binary to analyse}"
: "${SYMBOLIC_TIMEOUT:=600}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/symbolic"
RAW_DIR="${RESULTS_DIR}/raw"
NORM_DIR="${RESULTS_DIR}/normalized"
REPORT_DIR="${RESULTS_DIR}/reports"
mkdir -p "${RAW_DIR}" "${NORM_DIR}" "${REPORT_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success
ENGINE_EXIT=0

log_info "Starting symbolic execution"
log_info "  Engine  : ${SYMBOLIC_ENGINE}"
log_info "  Target  : ${TARGET_BINARY}"
log_info "  Timeout : ${SYMBOLIC_TIMEOUT}s"

case "${SYMBOLIC_ENGINE}" in
    angr)
        timeout "${SYMBOLIC_TIMEOUT}" \
            python3 /usr/local/lib/spt/angr-explore.py \
                "${TARGET_BINARY}" \
                "${RAW_DIR}/angr-results.json" \
            2>&1 | tee "${ARTIFACTS_DIR}/logs/symbolic.log" \
            || { ENGINE_EXIT=$?; STATUS=failure; log_warn "angr exited non-zero"; }
        ;;
    klee)
        command -v klee &>/dev/null || log_fatal "KLEE not found in PATH"
        timeout "${SYMBOLIC_TIMEOUT}" \
            klee --output-dir="${RAW_DIR}/klee-out" "${TARGET_BINARY}" \
            2>&1 | tee "${ARTIFACTS_DIR}/logs/symbolic.log" \
            || { ENGINE_EXIT=$?; STATUS=failure; log_warn "klee exited non-zero"; }
        ;;
    *)
        log_fatal "Unknown SYMBOLIC_ENGINE=${SYMBOLIC_ENGINE}; use angr|klee"
        ;;
esac

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))
ANGR_RESULTS="${RAW_DIR}/angr-results.json"
SUMMARY_JSON="${NORM_DIR}/symbolic-summary.json"
FINDING_COUNT=0
if [[ -f "${ANGR_RESULTS}" ]]; then
    FINDING_COUNT="$(python3 - "${ANGR_RESULTS}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(len(data.get("findings", [])))
PY
)"
else
    cat > "${ANGR_RESULTS}" <<JSON
{"schema_version":"1.0.0","tool":"${SYMBOLIC_ENGINE}","target":"${TARGET_BINARY}","status":"${STATUS}","error":"engine did not produce a raw result file","findings":[]}
JSON
fi

python3 - "${ANGR_RESULTS}" "${SUMMARY_JSON}" "${SYMBOLIC_ENGINE}" "${TARGET_BINARY}" "${STATUS}" "${DURATION}" <<'PY'
import json
import sys

raw_path, out_path, engine, target, status, duration = sys.argv[1:7]
raw = json.load(open(raw_path, "r", encoding="utf-8"))
summary = {
    "schema_version": "1.0.0",
    "engine": engine,
    "target": target,
    "status": status,
    "duration_seconds": int(duration),
    "finding_count": len(raw.get("findings", [])),
    "states_active": raw.get("states_active", 0),
    "states_deadended": raw.get("states_deadended", 0),
    "states_errored": raw.get("states_errored", 0),
    "states_unconstrained": raw.get("states_unconstrained", 0),
}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(summary, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

cat > "${REPORT_DIR}/symbolic-summary.md" <<EOF
# Symbolic Summary

- Engine: ${SYMBOLIC_ENGINE}
- Target: ${TARGET_BINARY}
- Status: ${STATUS}
- Findings: ${FINDING_COUNT}
EOF

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{"schema_version":"1.0.0","tool":"symbolic","target":"${TARGET_BINARY}","summary":{"total":${FINDING_COUNT},"critical":0,"high":${FINDING_COUNT},"medium":0,"low":0,"info":0},"findings":[]}
JSON

emit-job-report \
    --tool symbolic \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "symbolic_engine=${SYMBOLIC_ENGINE}" \
    --extra "finding_count=${FINDING_COUNT}"

log_info "Symbolic execution finished (${STATUS}) in ${DURATION}s"

if [[ "${STATUS}" != "success" ]]; then
    exit "${ENGINE_EXIT:-1}"
fi
