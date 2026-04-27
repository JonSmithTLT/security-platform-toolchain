#!/usr/bin/env bash
# Store and restore generated release SBOM evidence by content digest.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

source "${ROOT_DIR}/scripts/artifact-cache.sh"

ACTION="${1:-}"
TAG="${TAG:-latest}"
RELEASE_EVIDENCE_DIR="${RELEASE_EVIDENCE_DIR:-artifacts/release-evidence/${TAG}}"
RELEASE_SBOMS_DIGEST="${RELEASE_SBOMS_DIGEST:-}"

usage() {
    cat >&2 <<'EOF'
Usage: scripts/cache-release-sboms.sh store|restore|info

Environment:
  TAG                    Release tag, default: latest
  RELEASE_EVIDENCE_DIR   Release evidence root, default: artifacts/release-evidence/TAG
  RELEASE_SBOMS_DIGEST   Required for restore/info unless SBOMs already exist
  SPT_ARTIFACT_CACHE     Cache root, default: $HOME/.spt-artifact-cache
EOF
}

sbom_file_list() {
    local evidence_dir="$1"
    [[ -d "${evidence_dir}/images" ]] || return 1
    (
        cd "${evidence_dir}"
        find images -path '*/sbom/*' -type f -print0 | sort -z
    )
}

sbom_tree_digest() {
    local evidence_dir="$1"
    local digest

    if ! sbom_file_list "${evidence_dir}" >/dev/null; then
        printf 'ERROR: SBOM evidence directory not found: %s/images\n' "${evidence_dir}" >&2
        return 2
    fi

    digest="$(
        cd "${evidence_dir}"
        find images -path '*/sbom/*' -type f -print0 \
            | sort -z \
            | xargs -0 sha256sum \
            | sha256sum \
            | awk '{print $1}'
    )"
    [[ -n "${digest}" ]] || {
        printf 'ERROR: no SBOM files found under %s/images/*/sbom\n' "${evidence_dir}" >&2
        return 2
    }
    printf '%s' "${digest}"
}

cache_key_for_digest() {
    local digest="$1"
    printf 'release-sboms-sha256-%s' "${digest}"
}

stage_for_store() {
    local stage_dir="$1"
    mkdir -p "${stage_dir}"

    (
        cd "${RELEASE_EVIDENCE_DIR}"
        find images -path '*/sbom/*' -type f -print0 | sort -z |
            while IFS= read -r -d '' rel; do
                mkdir -p "${stage_dir}/$(dirname "${rel}")"
                cp -a "${rel}" "${stage_dir}/${rel}"
            done
    )

    sbom_tree_digest "${RELEASE_EVIDENCE_DIR}" > "${stage_dir}/release-sboms.tree.sha256"
}

store_sboms() {
    local digest key stage_dir
    digest="$(sbom_tree_digest "${RELEASE_EVIDENCE_DIR}")"
    key="$(cache_key_for_digest "${digest}")"
    stage_dir="$(mktemp -d)"
    trap 'rm -rf "${stage_dir}"' RETURN

    stage_for_store "${stage_dir}"
    spt_cache_store "${key}" "${stage_dir}" "release-sboms:${TAG}"

    printf 'Cached release SBOM digest: sha256:%s\n' "${digest}"
    printf 'Cache key: %s\n' "${key}"
    printf 'Cache root: %s\n' "${SPT_ARTIFACT_CACHE}"
}

resolve_digest() {
    if [[ -n "${RELEASE_SBOMS_DIGEST}" ]]; then
        printf '%s' "${RELEASE_SBOMS_DIGEST#sha256:}"
        return 0
    fi
    sbom_tree_digest "${RELEASE_EVIDENCE_DIR}"
}

restore_sboms() {
    local digest key actual
    digest="$(resolve_digest)"
    key="$(cache_key_for_digest "${digest}")"
    mkdir -p "${RELEASE_EVIDENCE_DIR}"

    if ! spt_cache_restore "${key}" "${RELEASE_EVIDENCE_DIR}"; then
        printf 'ERROR: no cached release SBOMs for sha256:%s\n' "${digest}" >&2
        printf 'Cache key: %s\n' "${key}" >&2
        return 1
    fi

    actual="$(sbom_tree_digest "${RELEASE_EVIDENCE_DIR}")"
    if [[ "${actual}" != "${digest}" ]]; then
        printf 'ERROR: restored SBOM tree checksum mismatch\n' >&2
        printf 'expected %s\nactual   %s\n' "${digest}" "${actual}" >&2
        return 1
    fi
    printf '%s\n' "${actual}" > "${RELEASE_EVIDENCE_DIR}/release-sboms.tree.sha256"

    printf 'Restored release SBOM digest: sha256:%s\n' "${digest}"
    printf 'Release evidence directory: %s\n' "${RELEASE_EVIDENCE_DIR}"
}

info_sboms() {
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
        store_sboms
        ;;
    restore)
        restore_sboms
        ;;
    info)
        info_sboms
        ;;
    *)
        usage
        exit 2
        ;;
esac
