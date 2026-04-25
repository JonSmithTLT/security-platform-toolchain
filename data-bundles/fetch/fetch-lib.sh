#!/usr/bin/env bash
# Shared helpers for data bundle fetch scripts.

set -euo pipefail

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
    curl -fsSL --retry 3 --retry-delay 2 "${url}" -o "${out}"
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
