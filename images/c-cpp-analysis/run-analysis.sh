#!/usr/bin/env bash
# images/c-cpp-analysis/run-analysis.sh
# Runs cppcheck and clang-tidy against $TARGET_REPO, writes normalised results.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${TARGET_REPO:=/workspace}"
: "${ARTIFACTS_DIR:=/artifacts}"
: "${CPPCHECK_SEVERITY:=warning}"
: "${CLANG_TIDY_CHECKS:=-*,clang-analyzer-*,cert-*,bugprone-*}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/c-cpp-analysis"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}"

START_TIME=$(date +%s)
STATUS=success

log_info "Starting C/C++ analysis on ${TARGET_REPO}"

# ── cppcheck ───────────────────────────────────────────────────────────────
log_info "Running cppcheck (severity=${CPPCHECK_SEVERITY})"
cppcheck \
    --enable=all \
    --severity="${CPPCHECK_SEVERITY}" \
    --output-file="${RAW_DIR}/cppcheck.xml" \
    --xml --xml-version=2 \
    --suppress=missingIncludeSystem \
    "${TARGET_REPO}" 2>&1 | tee "${ARTIFACTS_DIR}/logs/c-cpp-analysis.log" \
    || { STATUS=failure; log_warn "cppcheck exited non-zero"; }

# ── clang-tidy ─────────────────────────────────────────────────────────────
if command -v clang-tidy &>/dev/null && [[ -f "${TARGET_REPO}/compile_commands.json" ]]; then
    log_info "Running clang-tidy (checks=${CLANG_TIDY_CHECKS})"
    find "${TARGET_REPO}" -name '*.cpp' -o -name '*.c' | head -200 | \
        xargs clang-tidy -checks="${CLANG_TIDY_CHECKS}" \
            -p "${TARGET_REPO}" 2>&1 \
        | tee -a "${ARTIFACTS_DIR}/logs/c-cpp-analysis.log" \
        > "${RAW_DIR}/clang-tidy.txt" \
        || { STATUS=failure; log_warn "clang-tidy exited non-zero"; }
else
    log_warn "compile_commands.json not found; skipping clang-tidy"
fi

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

# ── Emit job report ────────────────────────────────────────────────────────
emit-job-report \
    --tool c-cpp-analysis \
    --status "${STATUS}" \
    --extra "duration_seconds=${DURATION}"

log_info "C/C++ analysis finished (${STATUS}) in ${DURATION}s"
