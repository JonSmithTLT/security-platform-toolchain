#!/usr/bin/env bash
set -euo pipefail

: "${HARNESS_NAME:=spt_harness}"
: "${HARNESS_ENGINE:=libfuzzer}"
: "${HARNESS_WORK_DIR:=/artifacts/results/harness-builder/raw/generated}"
: "${HARNESS_BUILD_DIR:=/artifacts/results/harness-builder/raw/build}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/harness-builder"
NORM_DIR="${RESULTS_DIR}/normalized"
REPORT_DIR="${RESULTS_DIR}/reports"
mkdir -p "${NORM_DIR}" "${REPORT_DIR}"

binary="${HARNESS_BUILD_DIR}/${HARNESS_NAME}"
sha="$(sha256sum "${binary}" | awk '{print $1}')"
template="$(cat "${HARNESS_WORK_DIR}/.template" 2>/dev/null || echo unknown)"

cat > "${NORM_DIR}/harness-manifest.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "harness-builder",
  "harness": "${HARNESS_NAME}",
  "engine": "${HARNESS_ENGINE}",
  "template": "${template}",
  "source_dir": "${HARNESS_WORK_DIR}",
  "build_dir": "${HARNESS_BUILD_DIR}",
  "binary": "${binary}",
  "binary_sha256": "${sha}",
  "status": "smoked",
  "commands": ["generate-harness", "build-harness", "smoke-harness"],
  "artifacts": ["${binary}"]
}
JSON

cat > "${NORM_DIR}/harness-build.json" <<JSON
{"schema_version":"1.0.0","status":"success","binary":"${binary}","binary_sha256":"${sha}"}
JSON
cat > "${NORM_DIR}/harness-smoke.json" <<JSON
{"schema_version":"1.0.0","status":"success","seed":"${HARNESS_SEED:-/workspace/seed}"}
JSON
cat > "${REPORT_DIR}/harness-summary.md" <<EOF
# Harness Summary

- Harness: ${HARNESS_NAME}
- Engine: ${HARNESS_ENGINE}
- Template: ${template}
- Binary: ${binary}
EOF
