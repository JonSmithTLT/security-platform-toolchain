#!/usr/bin/env bash
# images/replay-runner/run-replay.sh
# Replays crash / PoC inputs against a target binary, captures crash details.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${REPLAY_TARGET:?REPLAY_TARGET must be set to the target binary path}"
: "${CRASH_DIR:=/workspace/crashes}"
: "${ARTIFACTS_DIR:=/artifacts}"
: "${REPLAY_TIMEOUT:=30}"
: "${REPLAY_USE_VALGRIND:=0}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/replay-runner"
EVIDENCE_DIR="${RESULTS_DIR}/evidence"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${EVIDENCE_DIR}" "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
CRASHES_REPRODUCED=0
CRASHES_TOTAL=0

log_info "Starting replay runner"
log_info "  Target      : ${REPLAY_TARGET}"
log_info "  Crash dir   : ${CRASH_DIR}"
log_info "  Timeout/run : ${REPLAY_TIMEOUT}s"

REPLAY_RESULTS="${RAW_DIR}/replay-results.json"
echo "[]" > "${REPLAY_RESULTS}"

find "${CRASH_DIR}" -type f | sort | while read -r crash; do
    CRASHES_TOTAL=$(( CRASHES_TOTAL + 1 ))
    CRASH_NAME="$(basename "${crash}")"
    log_info "Replaying ${CRASH_NAME}"

    CMD=("${REPLAY_TARGET}" "${crash}")
    if [[ "${REPLAY_USE_VALGRIND}" == "1" ]]; then
        CMD=(valgrind --error-exitcode=99 --track-origins=yes "${REPLAY_TARGET}" "${crash}")
    fi

    EXIT_CODE=0
    OUTPUT=""
    OUTPUT=$(timeout "${REPLAY_TIMEOUT}" "${CMD[@]}" 2>&1) || EXIT_CODE=$?

    REPRODUCED=false
    # Signals 6 (SIGABRT), 11 (SIGSEGV), 4 (SIGILL) indicate a crash
    if (( EXIT_CODE > 128 )) || [[ "${OUTPUT}" == *"SIGSEGV"* ]] || \
       [[ "${OUTPUT}" == *"heap-buffer-overflow"* ]]; then
        REPRODUCED=true
        CRASHES_REPRODUCED=$(( CRASHES_REPRODUCED + 1 ))
        cp "${crash}" "${EVIDENCE_DIR}/${CRASH_NAME}"
        log_warn "  REPRODUCED (exit=${EXIT_CODE})"
    else
        log_info "  Not reproduced (exit=${EXIT_CODE})"
    fi

    # Append to results JSON
    jq --arg name "${CRASH_NAME}" \
       --arg reproduced "${REPRODUCED}" \
       --arg exit_code "${EXIT_CODE}" \
       --arg output "${OUTPUT}" \
       '. += [{"crash": $name, "reproduced": ($reproduced == "true"), "exit_code": ($exit_code | tonumber), "output": $output}]' \
       "${REPLAY_RESULTS}" > "${REPLAY_RESULTS}.tmp" && \
    mv "${REPLAY_RESULTS}.tmp" "${REPLAY_RESULTS}"
done

log_info "Reproduced ${CRASHES_REPRODUCED}/${CRASHES_TOTAL} crashes"

STATUS=success
[[ "${CRASHES_REPRODUCED}" -gt 0 ]] && STATUS=failure

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool replay-runner \
    --status "${STATUS}" \
    --extra "duration_seconds=${DURATION}" \
    --extra "crashes_total=${CRASHES_TOTAL}" \
    --extra "crashes_reproduced=${CRASHES_REPRODUCED}"

log_info "Replay runner finished (${STATUS}) in ${DURATION}s"
