#!/usr/bin/env bash
# images/intel-ingest/run-intel-ingest.sh
# Ingests offline intelligence documents into JSONL chunks.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${INTEL_INPUT:=/intel}"
: "${INTEL_DATASET:=local}"
: "${INTEL_VERSION:=unknown}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/intel-ingest"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

python3 /usr/local/lib/spt/intel-ingest.py \
    --input "${INTEL_INPUT}" \
    --dataset "${INTEL_DATASET}" \
    --version "${INTEL_VERSION}" \
    --chunks-out "${RAW_DIR}/chunks.jsonl" \
    --manifest-out "${RAW_DIR}/ingest-manifest.json" \
    2>&1 | tee "${ARTIFACTS_DIR}/logs/intel-ingest.log" \
    || { STATUS=failure; log_warn "intel ingestion failed"; }

CHUNK_COUNT=$(wc -l < "${RAW_DIR}/chunks.jsonl" 2>/dev/null || echo 0)

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "intel-ingest",
  "target": "${INTEL_INPUT}",
  "summary": {"total": 0, "critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0},
  "findings": []
}
JSON

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool intel-ingest \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "chunk_count=${CHUNK_COUNT}" \
    --extra "dataset=${INTEL_DATASET}" \
    --extra "dataset_version=${INTEL_VERSION}"
