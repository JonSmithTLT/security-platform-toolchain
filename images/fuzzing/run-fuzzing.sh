#!/usr/bin/env bash
# images/fuzzing/run-fuzzing.sh
# Runs AFL++ against a compiled fuzz target, then collects crash artefacts.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${FUZZ_TARGET:?FUZZ_TARGET must be set to the path of the instrumented binary}"
: "${FUZZ_TIMEOUT:=300}"
: "${FUZZ_CORPUS:=/workspace/corpus}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/fuzzing"
RAW_DIR="${RESULTS_DIR}/raw"
CRASH_DIR="${RESULTS_DIR}/evidence/crashes"
mkdir -p "${RAW_DIR}" "${CRASH_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

log_info "Starting AFL++ fuzz run"
log_info "  Target  : ${FUZZ_TARGET}"
log_info "  Timeout : ${FUZZ_TIMEOUT}s"
log_info "  Corpus  : ${FUZZ_CORPUS}"

mkdir -p "${FUZZ_CORPUS}"
# Seed corpus needs at least one file
if [[ -z "$(ls -A "${FUZZ_CORPUS}" 2>/dev/null)" ]]; then
    log_warn "Corpus directory is empty; creating minimal seed"
    echo "A" > "${FUZZ_CORPUS}/seed0"
fi

afl-fuzz \
    -i "${FUZZ_CORPUS}" \
    -o "${RAW_DIR}/afl-out" \
    -V "${FUZZ_TIMEOUT}" \
    -- "${FUZZ_TARGET}" @@ \
    2>&1 | tee "${ARTIFACTS_DIR}/logs/fuzzing.log" \
    || { STATUS=failure; log_warn "afl-fuzz exited non-zero"; }

# ── Collect crashes ────────────────────────────────────────────────────────
CRASH_COUNT=0
if [[ -d "${RAW_DIR}/afl-out/default/crashes" ]]; then
    cp -r "${RAW_DIR}/afl-out/default/crashes/." "${CRASH_DIR}/"
    CRASH_COUNT=$(find "${CRASH_DIR}" -type f | wc -l)
fi
log_info "Crashes found: ${CRASH_COUNT}"

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool fuzzing \
    --status "${STATUS}" \
    --extra "duration_seconds=${DURATION}" \
    --extra "crash_count=${CRASH_COUNT}"

log_info "Fuzzing finished (${STATUS}) in ${DURATION}s"
