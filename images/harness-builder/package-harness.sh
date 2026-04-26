#!/usr/bin/env bash
set -euo pipefail

: "${ARTIFACTS_DIR:=/artifacts}"
: "${HARNESS_WORK_DIR:=/tmp/spt-harness/generated}"
: "${HARNESS_BUILD_DIR:=/tmp/spt-harness/build}"
RESULTS_DIR="${ARTIFACTS_DIR}/results/harness-builder"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}"
rm -rf "${RAW_DIR}/generated" "${RAW_DIR}/build"
cp -R "${HARNESS_WORK_DIR}" "${RAW_DIR}/generated"
cp -R "${HARNESS_BUILD_DIR}" "${RAW_DIR}/build"
tar -czf "${RAW_DIR}/harness-package.tar.gz" -C "${RAW_DIR}" generated build
