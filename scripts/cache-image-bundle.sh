#!/usr/bin/env bash
# Store and restore offline image bundle artifacts by content digest.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

source "${ROOT_DIR}/scripts/artifact-cache.sh"

ACTION="${1:-}"
TAG="${TAG:-latest}"
BUNDLE_DIR="${BUNDLE_DIR:-offline-bundles/out}"
BUNDLE_TAR="${BUNDLE_TAR:-${BUNDLE_DIR}/spt-bundle-${TAG}.tar.gz}"
BUNDLE_MANIFEST="${BUNDLE_MANIFEST:-${BUNDLE_DIR}/spt-bundle-${TAG}.manifest.json}"
IMAGE_BUNDLE_DIGEST="${IMAGE_BUNDLE_DIGEST:-}"

usage() {
    cat >&2 <<'EOF'
Usage: scripts/cache-image-bundle.sh store|restore|info

Environment:
  TAG                  Bundle tag, default: latest
  BUNDLE_DIR           Bundle directory, default: offline-bundles/out
  BUNDLE_TAR           Bundle tar path, default: BUNDLE_DIR/spt-bundle-TAG.tar.gz
  BUNDLE_MANIFEST      Image inspect manifest path
  IMAGE_BUNDLE_DIGEST  Required for restore/info unless BUNDLE_TAR exists
  SPT_ARTIFACT_CACHE   Cache root, default: $HOME/.spt-artifact-cache
EOF
}

bundle_digest() {
    local tar_path="$1"
    [[ -f "${tar_path}" ]] || {
        printf 'ERROR: bundle tar not found: %s\n' "${tar_path}" >&2
        return 2
    }
    sha256sum "${tar_path}" | awk '{print $1}'
}

cache_key_for_digest() {
    local digest="$1"
    printf 'image-bundle-sha256-%s' "${digest}"
}

stage_for_store() {
    local stage_dir="$1"
    mkdir -p "${stage_dir}"

    cp -a "${BUNDLE_TAR}" "${stage_dir}/"
    [[ -f "${BUNDLE_TAR}.sha256" ]] && cp -a "${BUNDLE_TAR}.sha256" "${stage_dir}/"
    [[ -f "${BUNDLE_MANIFEST}" ]] && cp -a "${BUNDLE_MANIFEST}" "${stage_dir}/"

    local parts_sum="${BUNDLE_DIR}/spt-bundle-${TAG}.parts.sha256"
    if [[ -f "${parts_sum}" ]]; then
        cp -a "${parts_sum}" "${stage_dir}/"
    fi

    local part
    for part in "${BUNDLE_TAR}".part-*; do
        [[ -e "${part}" ]] || continue
        cp -a "${part}" "${stage_dir}/"
    done
}

store_bundle() {
    local digest key stage_dir
    digest="$(bundle_digest "${BUNDLE_TAR}")"
    key="$(cache_key_for_digest "${digest}")"
    stage_dir="$(mktemp -d)"
    trap 'rm -rf "${stage_dir}"' RETURN

    stage_for_store "${stage_dir}"
    spt_cache_store "${key}" "${stage_dir}" "image-bundle:${TAG}"

    printf 'Cached image bundle digest: sha256:%s\n' "${digest}"
    printf 'Cache key: %s\n' "${key}"
    printf 'Cache root: %s\n' "${SPT_ARTIFACT_CACHE}"
}

resolve_digest() {
    if [[ -n "${IMAGE_BUNDLE_DIGEST}" ]]; then
        printf '%s' "${IMAGE_BUNDLE_DIGEST#sha256:}"
        return 0
    fi
    bundle_digest "${BUNDLE_TAR}"
}

restore_bundle() {
    local digest key
    digest="$(resolve_digest)"
    key="$(cache_key_for_digest "${digest}")"
    mkdir -p "${BUNDLE_DIR}"

    if ! spt_cache_restore "${key}" "${BUNDLE_DIR}"; then
        printf 'ERROR: no cached image bundle for sha256:%s\n' "${digest}" >&2
        printf 'Cache key: %s\n' "${key}" >&2
        return 1
    fi

    printf 'Restored image bundle digest: sha256:%s\n' "${digest}"
    printf 'Bundle directory: %s\n' "${BUNDLE_DIR}"
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
