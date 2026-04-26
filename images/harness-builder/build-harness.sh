#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${HARNESS_NAME:=spt_harness}"
: "${HARNESS_WORK_DIR:=/artifacts/results/harness-builder/raw/generated}"
: "${HARNESS_BUILD_DIR:=/artifacts/results/harness-builder/raw/build}"

mkdir -p "${HARNESS_BUILD_DIR}"
if [[ -f "${HARNESS_WORK_DIR}/harness.c" ]]; then
    clang-format -i "${HARNESS_WORK_DIR}/harness.c" || true
fi
HARNESS_NAME="${HARNESS_NAME}" HARNESS_WORK_DIR="${HARNESS_WORK_DIR}" HARNESS_BUILD_DIR="${HARNESS_BUILD_DIR}" bash "${HARNESS_WORK_DIR}/build.sh"
file "${HARNESS_BUILD_DIR}/${HARNESS_NAME}" > "${HARNESS_BUILD_DIR}/file.txt"
log_info "Built harness ${HARNESS_BUILD_DIR}/${HARNESS_NAME}"
