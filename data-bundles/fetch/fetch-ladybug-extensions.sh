#!/usr/bin/env bash
# Fetch LadybugDB extensions needed by GitNexus for offline FTS/vector search.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=data-bundles/fetch/fetch-lib.sh
source "${SCRIPT_DIR}/fetch-lib.sh"

OUT_ROOT="${1:-data-bundles/sources}"
OUT_DIR="${OUT_ROOT}/ladybug-extensions"

: "${LADYBUG_EXTENSION_BASE_URL:=https://extension.ladybugdb.com}"
: "${LADYBUG_EXTENSION_VERSION:=v0.15.0}"
: "${LADYBUG_EXTENSION_VERSIONS:=${LADYBUG_EXTENSION_VERSION}}"
: "${LADYBUG_EXTENSION_PLATFORM:=linux_amd64}"
: "${LADYBUG_EXTENSIONS:=fts vector}"

log "Fetching LadybugDB extensions: ${LADYBUG_EXTENSIONS}"

fetched_count=0
for version in ${LADYBUG_EXTENSION_VERSIONS}; do
    mkdir -p "${OUT_DIR}/${version}/${LADYBUG_EXTENSION_PLATFORM}"
    for ext in ${LADYBUG_EXTENSIONS}; do
        ext_dir="${OUT_DIR}/${version}/${LADYBUG_EXTENSION_PLATFORM}/${ext}"
        ext_file="${ext_dir}/lib${ext}.lbug_extension"
        url="${LADYBUG_EXTENSION_BASE_URL}/${version}/${LADYBUG_EXTENSION_PLATFORM}/${ext}/lib${ext}.lbug_extension"
        if download "${url}" "${ext_file}"; then
            log "Fetched LadybugDB extension ${ext} (${version})"
            fetched_count=$((fetched_count + 1))
        else
            warn "Could not fetch LadybugDB extension ${ext} from ${url}"
            rm -f "${ext_file}"
        fi
    done
done

if [[ "${fetched_count}" -eq 0 ]]; then
    warn "No LadybugDB extensions were fetched; GitNexus offline extension smoke will fail until fts/vector extensions are staged."
fi

write_metadata "${OUT_DIR}" "LadybugDB extensions" "${LADYBUG_EXTENSION_BASE_URL}"
write_checksums "${OUT_DIR}"
