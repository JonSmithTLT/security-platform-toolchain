#!/usr/bin/env bash
# images/sbom/run-sbom.sh
# Generates an SBOM using Syft in the requested format.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${TARGET_REPO:=/workspace}"
: "${SBOM_FORMAT:=cyclonedx-json}"
: "${ARTIFACTS_DIR:=/artifacts}"

SBOM_DIR="${ARTIFACTS_DIR}/sbom"
RESULTS_DIR="${ARTIFACTS_DIR}/results/sbom"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${SBOM_DIR}" "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

# Derive a sensible file extension
case "${SBOM_FORMAT}" in
    cyclonedx-json) EXT=cyclonedx.json ;;
    cyclonedx-xml)  EXT=cyclonedx.xml  ;;
    spdx-json)      EXT=spdx.json      ;;
    spdx-tag-value) EXT=spdx.tv        ;;
    *)              EXT="${SBOM_FORMAT}";;
esac

SBOM_FILE="${SBOM_DIR}/sbom.${EXT}"
START_TIME=$(date +%s)
STATUS=success

log_info "Generating SBOM"
log_info "  Target : ${TARGET_REPO}"
log_info "  Format : ${SBOM_FORMAT}"
log_info "  Output : ${SBOM_FILE}"

syft "${TARGET_REPO}" \
    --output "${SBOM_FORMAT}=${SBOM_FILE}" \
    2>&1 | tee "${ARTIFACTS_DIR}/logs/sbom.log" \
    || { STATUS=failure; log_warn "syft exited non-zero"; }

COMPONENT_COUNT=0
if [[ -f "${SBOM_FILE}" && "${SBOM_FORMAT}" == cyclonedx-json ]]; then
    COMPONENT_COUNT=$(jq '.components | length' "${SBOM_FILE}" 2>/dev/null || echo 0)
fi
log_info "Components: ${COMPONENT_COUNT}"

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "sbom",
  "target": "${TARGET_REPO}",
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

cp "${SBOM_FILE}" "${RAW_DIR}/$(basename "${SBOM_FILE}")" 2>/dev/null || true

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool sbom \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "component_count=${COMPONENT_COUNT}" \
    --extra "sbom_format=${SBOM_FORMAT}"

log_info "SBOM generation finished (${STATUS}) in ${DURATION}s"
