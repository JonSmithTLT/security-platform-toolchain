#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/codeql-packs"
PACKS="${CODEQL_PACKS:-}"
REGISTRY="${REGISTRY:-registry.internal/security-platform}"
TAG="${TAG:-latest}"
CODEQL_IMAGE="${CODEQL_IMAGE:-${REGISTRY}/spt-codeql:${TAG}}"
USE_DOCKER="${CODEQL_USE_DOCKER:-auto}"

require_cmd sha256sum
mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"    # normalize to absolute — docker -v rejects relative paths
chmod 777 "${OUT_DIR}"                 # spt user (UID 1001) inside container must be able to write
if [[ -z "${PACKS}" ]]; then
    warn "CODEQL_PACKS is not set; copying repo-local queries"
    mkdir -p "${OUT_DIR}/local"
    cp -R queries/codeql/. "${OUT_DIR}/local/"
    write_metadata "${OUT_DIR}" "codeql-packs" "repo-local"
    write_checksums "${OUT_DIR}"
    exit 0
fi
if [[ "${USE_DOCKER}" != "0" ]] && command -v docker >/dev/null 2>&1 && docker image inspect "${CODEQL_IMAGE}" >/dev/null 2>&1; then
    log "Fetching CodeQL packs with ${CODEQL_IMAGE}: ${PACKS}"
    for pack in ${PACKS}; do
        docker run --rm \
            -v "${OUT_DIR}:/codeql-packs" \
            "${CODEQL_IMAGE}" \
            codeql pack download "${pack}" --dir /codeql-packs
    done
    write_metadata "${OUT_DIR}" "codeql-packs" "codeql pack download via ${CODEQL_IMAGE}"
    write_checksums "${OUT_DIR}"
    exit 0
fi

if ! command -v codeql >/dev/null 2>&1; then
    warn "codeql is not installed and ${CODEQL_IMAGE} is not available locally; cannot download packs: ${PACKS}"
    write_metadata "${OUT_DIR}" "codeql-packs" "manual"
    exit 0
fi

log "Fetching CodeQL packs: ${PACKS}"
for pack in ${PACKS}; do
    codeql pack download "${pack}" --dir "${OUT_DIR}"
done
write_metadata "${OUT_DIR}" "codeql-packs" "codeql pack download"
write_checksums "${OUT_DIR}"
