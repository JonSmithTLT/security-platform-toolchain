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

mkdir -p "${CORPUS_OUT}" "${ARTIFACTS_DIR}/logs"

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

emit-job-report \
    --tool corpus-tools \
    --status "${STATUS}" \
    --extra "duration_seconds=${DURATION}" \
    --extra "corpus_size=${CORPUS_SIZE}" \
    --extra "corpus_mode=${CORPUS_MODE}"

log_info "Corpus management (${CORPUS_MODE}) finished (${STATUS}) in ${DURATION}s — ${CORPUS_SIZE} files"
