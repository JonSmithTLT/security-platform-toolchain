#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${HARNESS_ENGINE:=libfuzzer}"
: "${HARNESS_NAME:=spt_harness}"
: "${HARNESS_TEMPLATE_DIR:=/opt/spt/harness-templates}"
: "${HARNESS_WORK_DIR:=/artifacts/results/harness-builder/raw/generated}"

template="${HARNESS_TEMPLATE:-${HARNESS_ENGINE}-c}"
src="${HARNESS_TEMPLATE_DIR}/${template}"
if [[ ! -d "${src}" ]]; then
    log_error "Harness template not found: ${src}"
    exit 1
fi

rm -rf "${HARNESS_WORK_DIR}"
mkdir -p "${HARNESS_WORK_DIR}"
cp -R "${src}/." "${HARNESS_WORK_DIR}/"
find "${HARNESS_WORK_DIR}" -name '*.sh' -type f -exec chmod +x {} + 2>/dev/null || true
printf '%s\n' "${template}" > "${HARNESS_WORK_DIR}/.template"
log_info "Generated ${template} harness at ${HARNESS_WORK_DIR}"
