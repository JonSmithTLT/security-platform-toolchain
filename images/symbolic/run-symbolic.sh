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
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

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
            || { STATUS=failure; log_warn "angr exited non-zero"; }
        ;;
    klee)
        command -v klee &>/dev/null || log_fatal "KLEE not found in PATH"
        timeout "${SYMBOLIC_TIMEOUT}" \
            klee --output-dir="${RAW_DIR}/klee-out" "${TARGET_BINARY}" \
            2>&1 | tee "${ARTIFACTS_DIR}/logs/symbolic.log" \
            || { STATUS=failure; log_warn "klee exited non-zero"; }
        ;;
    *)
        log_fatal "Unknown SYMBOLIC_ENGINE=${SYMBOLIC_ENGINE}; use angr|klee"
        ;;
esac

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool symbolic \
    --status "${STATUS}" \
    --extra "duration_seconds=${DURATION}" \
    --extra "symbolic_engine=${SYMBOLIC_ENGINE}"

log_info "Symbolic execution finished (${STATUS}) in ${DURATION}s"
