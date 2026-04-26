#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${FUZZ_TARGET:=}"
: "${FUZZ_CORPUS:=/workspace/corpus}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/fuzzing"
RAW_DIR="${RESULTS_DIR}/raw"
EVIDENCE_DIR="${RESULTS_DIR}/evidence"
NORM_DIR="${RESULTS_DIR}/normalized"
REPORT_DIR="${RESULTS_DIR}/reports"
mkdir -p "${RAW_DIR}/honggfuzz-out" "${EVIDENCE_DIR}/crashes" "${EVIDENCE_DIR}/hangs" "${EVIDENCE_DIR}/seeds" "${NORM_DIR}" "${REPORT_DIR}" "${ARTIFACTS_DIR}/logs"

emit_experimental_artifacts() {
    local status="$1"
    local message="$2"
    local target="${FUZZ_TARGET:-unknown}"
    cat > "${NORM_DIR}/fuzz-campaign.json" <<JSON
{
  "schema_version": "1.0.0",
  "engine": "honggfuzz",
  "engine_status": "experimental",
  "target": "${target}",
  "duration_seconds": 0,
  "exec_count": 0,
  "crash_count": 0,
  "hang_count": 0,
  "corpus_in": "${FUZZ_CORPUS}",
  "corpus_out": "${RAW_DIR}/honggfuzz-out",
  "replay_commands": [],
  "message": "${message}"
}
JSON
    cat > "${NORM_DIR}/crashes.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "crashes": []
}
JSON
    cat > "${REPORT_DIR}/fuzz-summary.md" <<EOF
# Fuzz Summary

- Engine: honggfuzz
- Engine status: experimental
- Status: ${status}
- Message: ${message}
EOF
    cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{"schema_version":"1.0.0","tool":"fuzzing","target":"${target}","summary":{"total":0,"critical":0,"high":0,"medium":0,"low":0,"info":0},"findings":[]}
JSON
}

if ! command -v honggfuzz >/dev/null 2>&1; then
    msg="honggfuzz support requested, but honggfuzz is not installed in this image build. AFL++ and libFuzzer are the first-class engines for v0.1.1."
    log_error "${msg}"
    echo "${msg}" > "${ARTIFACTS_DIR}/logs/fuzzing.log"
    emit_experimental_artifacts "unavailable" "${msg}"
    emit-job-report --tool fuzzing --status error --results-file "${RESULTS_DIR}/tool-result.json" --extra "engine=honggfuzz" --extra "engine_status=experimental" --extra "crash_count=0"
    exit 78
fi

if [[ -z "${FUZZ_TARGET}" ]]; then
    msg="FUZZ_ENGINE=honggfuzz selected, but FUZZ_TARGET is not set"
    log_error "${msg}"
    echo "${msg}" > "${ARTIFACTS_DIR}/logs/fuzzing.log"
    emit_experimental_artifacts "misconfigured" "${msg}"
    emit-job-report --tool fuzzing --status error --results-file "${RESULTS_DIR}/tool-result.json" --extra "engine=honggfuzz" --extra "engine_status=experimental" --extra "crash_count=0"
    exit 2
fi

HONGGFUZZ_PATH="$(command -v honggfuzz)"
HONGGFUZZ_HELP="$(honggfuzz 2>&1 | head -1 || true)"
msg="honggfuzz is installed at ${HONGGFUZZ_PATH}; v0.1.1 keeps it experimental and non-gating until artifact collection and replay metadata match AFL++/libFuzzer."
log_warn "${msg}"
{
    printf '%s\n' "${msg}"
    printf 'source_repo=%s\n' "${HONGGFUZZ_REPO:-https://github.com/google/honggfuzz.git}"
    printf 'source_ref=%s\n' "${HONGGFUZZ_REF:-unknown}"
    printf 'help=%s\n' "${HONGGFUZZ_HELP}"
} > "${ARTIFACTS_DIR}/logs/fuzzing.log"
emit_experimental_artifacts "experimental" "${msg}"
emit-job-report --tool fuzzing --status success --results-file "${RESULTS_DIR}/tool-result.json" --extra "engine=honggfuzz" --extra "engine_status=experimental" --extra "crash_count=0" --extra "honggfuzz_path=${HONGGFUZZ_PATH}" --extra "honggfuzz_source_ref=${HONGGFUZZ_REF:-unknown}"
