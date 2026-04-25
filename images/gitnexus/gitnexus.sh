#!/usr/bin/env bash
# images/gitnexus/gitnexus.sh
# Clone a git repository and optionally push/pull artifacts to/from Nexus.

set -euo pipefail
# shellcheck source=/usr/local/lib/spt/logging.sh
source /usr/local/lib/spt/logging.sh

: "${ARTIFACTS_DIR:=/artifacts}"
: "${GIT_REPO:=}"
: "${GIT_REF:=HEAD}"
: "${NEXUS_URL:=}"
: "${NEXUS_USER:=}"
: "${NEXUS_PASS:=}"
: "${NEXUS_REPO:=}"
: "${GITNEXUS_MODE:=clone}"   # clone | upload | download

WORKSPACE=/workspace
mkdir -p "${ARTIFACTS_DIR}/logs"

# ── Clone ─────────────────────────────────────────────────────────────────
_clone() {
    [[ -n "${GIT_REPO}" ]] || log_fatal "GIT_REPO is required for clone mode"
    log_info "Cloning ${GIT_REPO}@${GIT_REF} → ${WORKSPACE}"
    git clone --depth=1 "${GIT_REPO}" "${WORKSPACE}" 2>&1 | \
        tee "${ARTIFACTS_DIR}/logs/gitnexus.log"
    git -C "${WORKSPACE}" fetch --depth=1 origin "${GIT_REF}" 2>&1 | \
        tee -a "${ARTIFACTS_DIR}/logs/gitnexus.log"
    git -C "${WORKSPACE}" checkout FETCH_HEAD 2>&1 | \
        tee -a "${ARTIFACTS_DIR}/logs/gitnexus.log"
    log_info "Clone complete"
}

# ── Upload to Nexus ────────────────────────────────────────────────────────
_upload() {
    [[ -n "${NEXUS_URL}" ]]  || log_fatal "NEXUS_URL is required for upload mode"
    [[ -n "${NEXUS_REPO}" ]] || log_fatal "NEXUS_REPO is required for upload mode"
    log_info "Uploading artifacts from ${ARTIFACTS_DIR} to ${NEXUS_URL}/${NEXUS_REPO}"
    find "${ARTIFACTS_DIR}" -type f | while read -r file; do
        relative="${file#"${ARTIFACTS_DIR}/"}"
        log_info "  Uploading ${relative}"
        curl --fail --silent --show-error \
            -u "${NEXUS_USER}:${NEXUS_PASS}" \
            --upload-file "${file}" \
            "${NEXUS_URL}/repository/${NEXUS_REPO}/${relative}" 2>&1 | \
            tee -a "${ARTIFACTS_DIR}/logs/gitnexus.log"
    done
    log_info "Upload complete"
}

# ── Download from Nexus ────────────────────────────────────────────────────
_download() {
    [[ -n "${NEXUS_URL}" ]]  || log_fatal "NEXUS_URL is required for download mode"
    [[ -n "${NEXUS_REPO}" ]] || log_fatal "NEXUS_REPO is required for download mode"
    : "${NEXUS_PATH:?NEXUS_PATH must be set for download mode}"
    log_info "Downloading ${NEXUS_PATH} from ${NEXUS_URL}/${NEXUS_REPO}"
    curl --fail --silent --show-error \
        -u "${NEXUS_USER}:${NEXUS_PASS}" \
        -L "${NEXUS_URL}/repository/${NEXUS_REPO}/${NEXUS_PATH}" \
        -o "${ARTIFACTS_DIR}/$(basename "${NEXUS_PATH}")" 2>&1 | \
        tee "${ARTIFACTS_DIR}/logs/gitnexus.log"
    log_info "Download complete"
}

case "${GITNEXUS_MODE}" in
    clone)    _clone    ;;
    upload)   _upload   ;;
    download) _download ;;
    *) log_fatal "Unknown GITNEXUS_MODE=${GITNEXUS_MODE}; use clone|upload|download" ;;
esac

emit-job-report --tool gitnexus --status success
