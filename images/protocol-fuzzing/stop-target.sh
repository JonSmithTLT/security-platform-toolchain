#!/usr/bin/env bash
set -euo pipefail

: "${ARTIFACTS_DIR:=/artifacts}"
pid_file="${ARTIFACTS_DIR}/logs/target.pid"
if [[ -f "${pid_file}" ]]; then
    kill "$(cat "${pid_file}")" 2>/dev/null || true
fi
