#!/usr/bin/env bash
# Store and restore offline data bundle artifacts by content digest.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

source "${ROOT_DIR}/scripts/artifact-cache.sh"

ACTION="${1:-}"
TAG="${TAG:-latest}"
DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR:-data-bundles/out}"
DATA_BUNDLE_NAME="${DATA_BUNDLE_NAME:-spt-data-bundle}"
DATA_BUNDLE_TAR="${DATA_BUNDLE_TAR:-${DATA_BUNDLE_DIR}/${DATA_BUNDLE_NAME}-${TAG}.tar.gz}"
DATA_BUNDLE_DIGEST="${DATA_BUNDLE_DIGEST:-}"

usage() {
    cat >&2 <<'EOF'
Usage: scripts/cache-data-bundle.sh store|restore|info

Environment:
  TAG                 Bundle tag, default: latest
  DATA_BUNDLE_DIR     Bundle directory, default: data-bundles/out
  DATA_BUNDLE_NAME    Bundle name, default: spt-data-bundle
  DATA_BUNDLE_TAR     Bundle tar path, default: DATA_BUNDLE_DIR/DATA_BUNDLE_NAME-TAG.tar.gz
  DATA_BUNDLE_DIGEST  Required for restore/info unless DATA_BUNDLE_TAR exists
  SPT_ARTIFACT_CACHE  Cache root, default: $HOME/.spt-artifact-cache
EOF
}

bundle_digest() {
    local tar_path="$1"
    [[ -f "${tar_path}" ]] || {
        printf 'ERROR: data bundle tar not found: %s\n' "${tar_path}" >&2
        return 2
    }
    sha256sum "${tar_path}" | awk '{print $1}'
}

cache_key_for_digest() {
    local digest="$1"
    printf 'data-bundle-sha256-%s' "${digest}"
}

stage_for_store() {
    local stage_dir="$1"
    mkdir -p "${stage_dir}"

    cp -a "${DATA_BUNDLE_TAR}" "${stage_dir}/"
    [[ -f "${DATA_BUNDLE_TAR}.sha256" ]] && cp -a "${DATA_BUNDLE_TAR}.sha256" "${stage_dir}/"

    local manifest="${DATA_BUNDLE_DIR}/${DATA_BUNDLE_NAME}-${TAG}.manifest.json"
    local source_sums="${DATA_BUNDLE_DIR}/${DATA_BUNDLE_NAME}-${TAG}.source-checksums.sha256"
    local parts_sum="${DATA_BUNDLE_DIR}/${DATA_BUNDLE_NAME}-${TAG}.parts.sha256"

    [[ -f "${manifest}" ]] && cp -a "${manifest}" "${stage_dir}/"
    [[ -f "${source_sums}" ]] && cp -a "${source_sums}" "${stage_dir}/"
    [[ -f "${parts_sum}" ]] && cp -a "${parts_sum}" "${stage_dir}/"

    local part
    for part in "${DATA_BUNDLE_TAR}".part-*; do
        [[ -e "${part}" ]] || continue
        cp -a "${part}" "${stage_dir}/"
    done
}

store_bundle() {
    local digest key stage_dir
    digest="$(bundle_digest "${DATA_BUNDLE_TAR}")"
    key="$(cache_key_for_digest "${digest}")"
    stage_dir="$(mktemp -d)"
    trap 'rm -rf "${stage_dir}"' RETURN

    stage_for_store "${stage_dir}"
    spt_cache_store "${key}" "${stage_dir}" "data-bundle:${DATA_BUNDLE_NAME}:${TAG}"

    printf 'Cached data bundle digest: sha256:%s\n' "${digest}"
    printf 'Cache key: %s\n' "${key}"
    printf 'Cache root: %s\n' "${SPT_ARTIFACT_CACHE}"
}

resolve_digest() {
    if [[ -n "${DATA_BUNDLE_DIGEST}" ]]; then
        printf '%s' "${DATA_BUNDLE_DIGEST#sha256:}"
        return 0
    fi
    bundle_digest "${DATA_BUNDLE_TAR}"
}

restore_bundle() {
    local digest key
    digest="$(resolve_digest)"
    key="$(cache_key_for_digest "${digest}")"
    mkdir -p "${DATA_BUNDLE_DIR}"

    if ! spt_cache_restore "${key}" "${DATA_BUNDLE_DIR}"; then
        printf 'ERROR: no cached data bundle for sha256:%s\n' "${digest}" >&2
        printf 'Cache key: %s\n' "${key}" >&2
        return 1
    fi

    printf 'Restored data bundle digest: sha256:%s\n' "${digest}"
    printf 'Data bundle directory: %s\n' "${DATA_BUNDLE_DIR}"
}

info_bundle() {
    local digest key
    digest="$(resolve_digest)"
    key="$(cache_key_for_digest "${digest}")"
    spt_cache_info "${key}" || {
        printf 'No cache metadata for sha256:%s\n' "${digest}" >&2
        return 1
    }
}

case "${ACTION}" in
    store)
        store_bundle
        ;;
    restore)
        restore_bundle
        ;;
    info)
        info_bundle
        ;;
    *)
        usage
        exit 2
        ;;
esac
