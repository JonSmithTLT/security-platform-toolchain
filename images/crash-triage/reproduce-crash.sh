#!/usr/bin/env bash
set -euo pipefail

: "${REPRO_COMMAND:=}"
: "${ARTIFACTS_DIR:=/artifacts}"
mkdir -p "${ARTIFACTS_DIR}/logs"
if [[ -z "${REPRO_COMMAND}" ]]; then
    exit 0
fi
set +e
timeout "${REPRO_TIMEOUT:-30}" bash -lc "${REPRO_COMMAND}" > "${ARTIFACTS_DIR}/logs/reproduce.stdout" 2> "${ARTIFACTS_DIR}/logs/reproduce.stderr"
echo "$?" > "${ARTIFACTS_DIR}/logs/reproduce.exitcode"
