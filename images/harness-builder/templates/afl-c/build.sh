#!/usr/bin/env bash
set -euo pipefail
cc="${CC:-afl-clang-fast}"
"${cc}" -g -O1 -o "${HARNESS_BUILD_DIR}/${HARNESS_NAME}" "${HARNESS_WORK_DIR}/harness.c"
