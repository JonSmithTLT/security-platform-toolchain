#!/usr/bin/env bash
# images/corpus-tools/manage-corpus.sh
# Minimise, deduplicate, or merge fuzzing corpora.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${CORPUS_DIR:=/workspace/corpus}"
: "${CORPUS_OUT:=/artifacts/corpus-out}"
: "${CORPUS_MODE:=minimise}"   # minimise | merge | deduplicate
: "${CORPUS_TARGET:=}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/corpus-tools"
RAW_DIR="${RESULTS_DIR}/raw"
NORM_DIR="${RESULTS_DIR}/normalized"
REPORT_DIR="${RESULTS_DIR}/reports"
mkdir -p "${CORPUS_OUT}" "${RAW_DIR}" "${NORM_DIR}" "${REPORT_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

_minimise() {
    [[ -n "${CORPUS_TARGET}" ]] || log_fatal "CORPUS_TARGET required for minimise mode"
    log_info "Minimising corpus with afl-cmin"
    afl-cmin \
        -i "${CORPUS_DIR}" \
        -o "${CORPUS_OUT}" \
        -- "${CORPUS_TARGET}" @@ \
        2>&1 | tee "${ARTIFACTS_DIR}/logs/corpus-tools.log" \
        || { STATUS=failure; log_warn "afl-cmin exited non-zero"; }
}

_merge() {
    log_info "Merging corpus directories into ${CORPUS_OUT}"
    rsync -av "${CORPUS_DIR}/" "${CORPUS_OUT}/" \
        2>&1 | tee "${ARTIFACTS_DIR}/logs/corpus-tools.log"
}

_deduplicate() {
    log_info "Deduplicating corpus in ${CORPUS_DIR} → ${CORPUS_OUT}"
    # Use md5sum to remove duplicate byte-for-byte files
    declare -A SEEN
    mkdir -p "${CORPUS_OUT}"
    while IFS= read -r -d '' file; do
        HASH=$(md5sum "${file}" | awk '{print $1}')
        if [[ -z "${SEEN[$HASH]+_}" ]]; then
            SEEN[$HASH]=1
            cp "${file}" "${CORPUS_OUT}/"
        fi
    done < <(find "${CORPUS_DIR}" -type f -print0)
    DEDUP_COUNT=$(find "${CORPUS_OUT}" -type f | wc -l)
    log_info "Unique files after dedup: ${DEDUP_COUNT}"
}

case "${CORPUS_MODE}" in
    minimise)    _minimise    ;;
    merge)       _merge       ;;
    deduplicate) _deduplicate ;;
    *) log_fatal "Unknown CORPUS_MODE=${CORPUS_MODE}; use minimise|merge|deduplicate" ;;
esac

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))
CORPUS_SIZE=$(find "${CORPUS_OUT}" -type f | wc -l)
INPUT_COUNT=$(find "${CORPUS_DIR}" -type f 2>/dev/null | wc -l)
BYTES_BEFORE=$(find "${CORPUS_DIR}" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
BYTES_AFTER=$(find "${CORPUS_OUT}" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
UNIQUE_HASHES=$(find "${CORPUS_OUT}" -type f -exec sha256sum {} + 2>/dev/null | awk '{print $1}' | sort -u | wc -l)

find "${CORPUS_DIR}" -type f -exec sha256sum {} + 2>/dev/null > "${RAW_DIR}/input-corpus-manifest.json" || true
find "${CORPUS_OUT}" -type f -exec sha256sum {} + 2>/dev/null > "${RAW_DIR}/output-corpus-manifest.json" || true

cat > "${NORM_DIR}/corpus-summary.json" <<JSON
{
  "schema_version": "1.0.0",
  "input_file_count": ${INPUT_COUNT},
  "output_file_count": ${CORPUS_SIZE},
  "bytes_before": ${BYTES_BEFORE},
  "bytes_after": ${BYTES_AFTER},
  "unique_hashes": ${UNIQUE_HASHES},
  "duplicate_count": 0,
  "minimized_count": ${CORPUS_SIZE},
  "promoted_seeds": [],
  "rejected_seeds": []
}
JSON
cat > "${NORM_DIR}/corpus-delta.json" <<JSON
{"schema_version":"1.0.0","mode":"${CORPUS_MODE}","input_file_count":${INPUT_COUNT},"output_file_count":${CORPUS_SIZE}}
JSON
cat > "${REPORT_DIR}/corpus-summary.md" <<EOF
# Corpus Summary

- Mode: ${CORPUS_MODE}
- Input files: ${INPUT_COUNT}
- Output files: ${CORPUS_SIZE}
- Bytes before: ${BYTES_BEFORE}
- Bytes after: ${BYTES_AFTER}
EOF
cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{"schema_version":"1.0.0","tool":"corpus-tools","target":"${CORPUS_DIR}","summary":{"total":0,"critical":0,"high":0,"medium":0,"low":0,"info":0},"findings":[]}
JSON

emit-job-report \
    --tool corpus-tools \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "corpus_size=${CORPUS_SIZE}" \
    --extra "corpus_mode=${CORPUS_MODE}"

log_info "Corpus management (${CORPUS_MODE}) finished (${STATUS}) in ${DURATION}s — ${CORPUS_SIZE} files"
