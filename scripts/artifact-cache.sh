#!/usr/bin/env bash
# scripts/artifact-cache.sh
# Content-addressed artifact cache for expensive fetch and build operations.
#
# Cache layout:
#   ${SPT_ARTIFACT_CACHE}/<key>/
#     .spt-manifest.json   — key, source description, cached_at
#     .spt-checksums       — sha256sum of all cached files
#     <artifact files...>
#
# Usage:
#   source scripts/artifact-cache.sh
#   key=$(spt_cache_key "label" "$(cat lock.txt)")
#   if spt_cache_restore "${key}" "/output/dir"; then
#       echo "cache hit"
#   else
#       # do expensive work into /output/dir
#       spt_cache_store "${key}" "/output/dir" "label"
#   fi

: "${SPT_ARTIFACT_CACHE:=${HOME}/.spt-artifact-cache}"

spt_cache_key() {
    # Produce a deterministic cache key from any number of input strings.
    printf '%s\n' "$@" | sha256sum | awk '{print $1}'
}

spt_cache_valid() {
    local key="$1"
    local entry="${SPT_ARTIFACT_CACHE}/${key}"
    [[ -d "${entry}" ]] || return 1
    [[ -f "${entry}/.spt-checksums" ]] || return 1
    [[ -s "${entry}/.spt-checksums" ]] || return 0
    (cd "${entry}" && sha256sum -c .spt-checksums --quiet 2>/dev/null)
}

spt_cache_restore() {
    local key="$1"
    local out_dir="$2"
    spt_cache_valid "${key}" || return 1
    local entry="${SPT_ARTIFACT_CACHE}/${key}"
    mkdir -p "${out_dir}"
    # Copy everything except cache internals
    rsync -a --exclude='.spt-*' "${entry}/" "${out_dir}/" 2>/dev/null \
        || { find "${entry}" -mindepth 1 ! -name '.spt-*' -exec cp -a {} "${out_dir}/" \; ; }
    return 0
}

spt_cache_store() {
    local key="$1"
    local in_dir="$2"
    local label="${3:-unknown}"
    local entry="${SPT_ARTIFACT_CACHE}/${key}"

    rm -rf "${entry}"
    mkdir -p "${entry}"
    rsync -a --exclude='.spt-*' "${in_dir}/" "${entry}/" 2>/dev/null \
        || cp -a "${in_dir}/." "${entry}/"

    # Write manifest
    cat > "${entry}/.spt-manifest.json" <<JSON
{
  "key": "${key}",
  "label": "${label}",
  "cached_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "source_dir": "${in_dir}"
}
JSON

    # Write checksums of cached content (excluding internals)
    (
        cd "${entry}"
        mapfile -d '' files < <(find . -type f ! -name '.spt-*' -print0 | sort -z)
        if ((${#files[@]} > 0)); then
            printf '%s\0' "${files[@]}" | xargs -0 sha256sum > .spt-checksums
        else
            : > .spt-checksums
        fi
    )
}

spt_cache_info() {
    local key="$1"
    local entry="${SPT_ARTIFACT_CACHE}/${key}"
    [[ -f "${entry}/.spt-manifest.json" ]] && cat "${entry}/.spt-manifest.json"
}

spt_cache_invalidate() {
    local key="$1"
    rm -rf "${SPT_ARTIFACT_CACHE:?}/${key}"
}

spt_cache_size() {
    [[ -d "${SPT_ARTIFACT_CACHE}" ]] && du -sh "${SPT_ARTIFACT_CACHE}" 2>/dev/null | awk '{print $1}'
}
