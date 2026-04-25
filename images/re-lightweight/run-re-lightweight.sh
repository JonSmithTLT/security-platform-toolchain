#!/usr/bin/env bash
# images/re-lightweight/run-re-lightweight.sh
# Performs cheap binary/file triage without heavyweight RE tooling.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${RE_TARGET:=/workspace}"
: "${RE_MAX_FILES:=100}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/re-lightweight"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success
INVENTORY="${RAW_DIR}/inventory.jsonl"
: > "${INVENTORY}"

log_info "Running lightweight RE triage"
log_info "  Target : ${RE_TARGET}"

find "${RE_TARGET}" -type f | head -n "${RE_MAX_FILES}" | while IFS= read -r path; do
    mime="$(file -b --mime-type "${path}" 2>/dev/null || true)"
    desc="$(file -b "${path}" 2>/dev/null || true)"
    sha="$(sha256sum "${path}" | awk '{print $1}')"
    size="$(stat -c '%s' "${path}" 2>/dev/null || echo 0)"
    strings_out="${RAW_DIR}/$(basename "${path}").strings.txt"
    strings -a -n 6 "${path}" 2>/dev/null | head -200 > "${strings_out}" || true
    jq -nc \
        --arg path "${path}" \
        --arg mime "${mime}" \
        --arg desc "${desc}" \
        --arg sha256 "${sha}" \
        --argjson size "${size}" \
        '{path:$path,mime_type:$mime,description:$desc,sha256:$sha256,size_bytes:$size}' \
        >> "${INVENTORY}"
done 2>&1 | tee "${ARTIFACTS_DIR}/logs/re-lightweight.log"

FILE_COUNT=$(wc -l < "${INVENTORY}" 2>/dev/null || echo 0)

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "re-lightweight",
  "target": "${RE_TARGET}",
  "summary": {
    "total": 0,
    "critical": 0,
    "high": 0,
    "medium": 0,
    "low": 0,
    "info": 0
  },
  "findings": []
}
JSON

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool re-lightweight \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "file_count=${FILE_COUNT}"

log_info "Lightweight RE triage finished (${STATUS}) in ${DURATION}s"
