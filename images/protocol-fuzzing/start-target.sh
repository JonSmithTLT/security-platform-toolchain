#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${TARGET_START_CMD:=}"
: "${ARTIFACTS_DIR:=/artifacts}"

mkdir -p "${ARTIFACTS_DIR}/logs"
if [[ -z "${TARGET_START_CMD}" ]]; then
    log_info "No TARGET_START_CMD set"
    exit 0
fi

bash -lc "${TARGET_START_CMD}" > "${ARTIFACTS_DIR}/logs/target.log" 2>&1 &
echo "$!" > "${ARTIFACTS_DIR}/logs/target.pid"
sleep 1
log_info "Started target pid $(cat "${ARTIFACTS_DIR}/logs/target.pid")"
