#!/usr/bin/env bash
# Shared helpers for data bundle fetch scripts.

set -euo pipefail

FETCH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FETCH_ROOT_DIR="$(cd "${FETCH_LIB_DIR}/../.." && pwd)"
source "${FETCH_ROOT_DIR}/scripts/artifact-cache.sh"

log() {
    printf '==> %s\n' "$*"
}

warn() {
    printf 'WARN: %s\n' "$*" >&2
}

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        printf 'missing required command: %s\n' "${cmd}" >&2
        return 1
    fi
}

download() {
    local url="$1"
    local out="$2"
    mkdir -p "$(dirname "${out}")"
    log "Downloading ${url}"
    curl -fsSL \
        --retry "${FETCH_CURL_RETRIES:-3}" \
        --retry-delay "${FETCH_CURL_RETRY_DELAY:-2}" \
        --connect-timeout "${FETCH_CURL_CONNECT_TIMEOUT:-30}" \
        --max-time "${FETCH_CURL_MAX_TIME:-900}" \
        "${url}" \
        -o "${out}"
}

write_metadata() {
    local dir="$1"
    local source_name="$2"
    local source_url="$3"
    local fetched_at
    fetched_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    mkdir -p "${dir}"
    cat > "${dir}/metadata.json" <<JSON
{
  "source": "${source_name}",
  "source_url": "${source_url}",
  "fetched_at": "${fetched_at}"
}
JSON
}

write_checksums() {
    local dir="$1"
    if find "${dir}" -type f ! -name SHA256SUMS ! -name metadata.json | grep -q .; then
        (
            cd "${dir}"
            find . -type f ! -name SHA256SUMS ! -name metadata.json -print0 \
                | sort -z \
                | xargs -0 sha256sum > SHA256SUMS
        )
    fi
}

is_data_current() {
    # Returns 0 (true) if the directory has a valid SHA256SUMS that passes
    # verification — meaning previously fetched data is intact and unchanged.
    # Fetch scripts use this to skip re-downloads when nothing has changed.
    # Pass FORCE_FETCH=1 to bypass.
    local dir="$1"
    [[ "${FORCE_FETCH:-0}" == "1" ]] && return 1
    [[ -f "${dir}/SHA256SUMS" ]] || return 1
    [[ -f "${dir}/metadata.json" ]] || return 1
    (cd "${dir}" && sha256sum -c SHA256SUMS --quiet 2>/dev/null)
}

dataset_cache_key() {
    local source_name="$1"
    shift
    spt_cache_key "dataset-cache-v1" "${source_name}" "$@"
}

restore_dataset_cache() {
    local source_name="$1"
    local key="$2"
    local out_dir="$3"

    [[ "${FORCE_FETCH:-0}" == "1" ]] && return 1
    if spt_cache_restore "${key}" "${out_dir}"; then
        log "Dataset cache hit for ${source_name} (key=${key:0:12}...)"
        return 0
    fi
    return 1
}

store_dataset_cache() {
    local source_name="$1"
    local key="$2"
    local out_dir="$3"

    if [[ -f "${out_dir}/SHA256SUMS" ]]; then
        spt_cache_store "${key}" "${out_dir}" "dataset:${source_name}"
        log "Dataset cache stored for ${source_name} (key=${key:0:12}...)"
    fi
}
