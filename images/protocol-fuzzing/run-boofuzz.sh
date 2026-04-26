#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${BOOFUZZ_SCRIPT:=/usr/local/lib/spt/toy-boofuzz-campaign.py}"
: "${PROTOCOL_TARGET_HOST:=127.0.0.1}"
: "${PROTOCOL_TARGET_PORT:=9001}"
: "${ARTIFACTS_DIR:=/artifacts}"

RAW_DIR="${ARTIFACTS_DIR}/results/protocol-fuzzing/raw/boofuzz-results"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"
log_info "Running boofuzz campaign script ${BOOFUZZ_SCRIPT}"
python3 "${BOOFUZZ_SCRIPT}" --host "${PROTOCOL_TARGET_HOST}" --port "${PROTOCOL_TARGET_PORT}" --out "${RAW_DIR}" \
    2>&1 | tee "${ARTIFACTS_DIR}/logs/boofuzz.log"
