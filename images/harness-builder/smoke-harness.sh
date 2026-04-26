#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${HARNESS_ENGINE:=libfuzzer}"
: "${HARNESS_NAME:=spt_harness}"
: "${HARNESS_BUILD_DIR:=/artifacts/results/harness-builder/raw/build}"
: "${HARNESS_SEED:=/tmp/spt-harness/corpus/seed}"
: "${ARTIFACTS_DIR:=/artifacts}"

mkdir -p "$(dirname "${HARNESS_SEED}")" "${ARTIFACTS_DIR}/logs"
printf 'FUZZ' > "${HARNESS_SEED}"
binary="${HARNESS_BUILD_DIR}/${HARNESS_NAME}"

case "${HARNESS_ENGINE}" in
    afl)
        "${binary}" "${HARNESS_SEED}" > "${ARTIFACTS_DIR}/logs/harness-smoke.log" 2>&1
        ;;
    libfuzzer)
        corpus_dir="$(dirname "${HARNESS_SEED}")"
        "${binary}" "${corpus_dir}" -runs=1 > "${ARTIFACTS_DIR}/logs/harness-smoke.log" 2>&1
        ;;
    *)
        log_error "Unsupported smoke engine: ${HARNESS_ENGINE}"
        exit 1
        ;;
esac
log_info "Harness smoke passed"
