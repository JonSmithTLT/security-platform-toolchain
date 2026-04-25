#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/codeql-packs"
PACKS="${CODEQL_PACKS:-}"

require_cmd sha256sum
mkdir -p "${OUT_DIR}"
if [[ -z "${PACKS}" ]]; then
    warn "CODEQL_PACKS is not set; copying repo-local queries"
    mkdir -p "${OUT_DIR}/local"
    cp -R queries/codeql/. "${OUT_DIR}/local/"
    write_metadata "${OUT_DIR}" "codeql-packs" "repo-local"
    write_checksums "${OUT_DIR}"
    exit 0
fi
if ! command -v codeql >/dev/null 2>&1; then
    warn "codeql is not installed; cannot download packs: ${PACKS}"
    write_metadata "${OUT_DIR}" "codeql-packs" "manual"
    exit 0
fi
log "Fetching CodeQL packs: ${PACKS}"
for pack in ${PACKS}; do
    codeql pack download "${pack}" --dir "${OUT_DIR}"
done
write_metadata "${OUT_DIR}" "codeql-packs" "codeql pack download"
write_checksums "${OUT_DIR}"
