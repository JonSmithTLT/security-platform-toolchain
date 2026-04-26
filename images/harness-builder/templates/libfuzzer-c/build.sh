#!/usr/bin/env bash
set -euo pipefail
clang -g -O1 -fsanitize=fuzzer,address,undefined -o "${HARNESS_BUILD_DIR}/${HARNESS_NAME}" "${HARNESS_WORK_DIR}/harness.c"
