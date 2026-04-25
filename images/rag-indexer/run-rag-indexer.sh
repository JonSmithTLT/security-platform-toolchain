#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${RAG_INPUT:=/artifacts/results/intel-ingest/raw/chunks.jsonl}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/rag-indexer"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

python3 /usr/local/lib/spt/rag-indexer.py \
    --input "${RAG_INPUT}" \
    --sqlite-out "${RAW_DIR}/rag-index.sqlite" \
    --manifest-out "${RAW_DIR}/rag-index-manifest.json" \
    2>&1 | tee "${ARTIFACTS_DIR}/logs/rag-indexer.log" \
    || { STATUS=failure; log_warn "rag index creation failed"; }

DOC_COUNT=$(jq '.document_count // 0' "${RAW_DIR}/rag-index-manifest.json" 2>/dev/null || echo 0)

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "rag-indexer",
  "target": "${RAG_INPUT}",
  "summary": {"total": 0, "critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0},
  "findings": []
}
JSON

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool rag-indexer \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "document_count=${DOC_COUNT}"
