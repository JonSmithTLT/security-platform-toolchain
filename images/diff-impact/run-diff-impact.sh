#!/usr/bin/env bash
# images/diff-impact/run-diff-impact.sh
# Summarises changed files and nearby generated artifacts.

set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${TARGET_REPO:=/workspace}"
: "${DIFF_BASE:=}"
: "${DIFF_HEAD:=HEAD}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/diff-impact"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success
CHANGED="${RAW_DIR}/changed-files.txt"
IMPACT="${RAW_DIR}/impact.json"

log_info "Calculating diff impact"
log_info "  Repo : ${TARGET_REPO}"

if git -C "${TARGET_REPO}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "${DIFF_BASE}" ]]; then
        git -C "${TARGET_REPO}" diff --name-only "${DIFF_BASE}" "${DIFF_HEAD}" > "${CHANGED}"
    else
        git -C "${TARGET_REPO}" status --short | awk '{print $2}' > "${CHANGED}"
    fi
else
    find "${TARGET_REPO}" -type f | sed "s#^${TARGET_REPO}/##" > "${CHANGED}"
fi 2>&1 | tee "${ARTIFACTS_DIR}/logs/diff-impact.log"

FILE_COUNT=$(grep -cve '^[[:space:]]*$' "${CHANGED}" 2>/dev/null || echo 0)

jq -Rn --arg repo "${TARGET_REPO}" '
  [inputs | select(length > 0)] as $files |
  {
    schema_version: "1.0.0",
    target: $repo,
    changed_file_count: ($files | length),
    changed_files: $files
  }' "${CHANGED}" > "${IMPACT}"

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "diff-impact",
  "target": "${TARGET_REPO}",
  "summary": {"total": 0, "critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0},
  "findings": []
}
JSON

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool diff-impact \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "changed_file_count=${FILE_COUNT}"
