#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TAG="${TAG:-latest}"
BUNDLE_DIR="${BUNDLE_DIR:-offline-bundles/out}"
TAR="${BUNDLE_DIR}/spt-bundle-${TAG}.tar.gz"
PART_SUMS="${BUNDLE_DIR}/spt-bundle-${TAG}.parts.sha256"
TAR_SUM="${TAR}.sha256"

verify_sha256_file() {
    local sums_file="$1"
    local base_dir="$2"
    local expected path actual check_path

    while read -r expected path; do
        [[ -n "${expected}" && -n "${path}" ]] || continue
        check_path="${path}"
        if [[ ! -f "${check_path}" ]]; then
            check_path="${base_dir}/$(basename "${path}")"
        fi
        if [[ ! -f "${check_path}" ]]; then
            printf 'ERROR: checksum target not found: %s\n' "${path}" >&2
            return 1
        fi
        actual="$(sha256sum "${check_path}" | awk '{print $1}')"
        if [[ "${actual}" != "${expected}" ]]; then
            printf 'ERROR: checksum mismatch: %s\n' "${check_path}" >&2
            printf 'expected %s\nactual   %s\n' "${expected}" "${actual}" >&2
            return 1
        fi
        printf '%s: OK\n' "${check_path}"
    done < "${sums_file}"
}

if [[ -f "${PART_SUMS}" ]]; then
    verify_sha256_file "${PART_SUMS}" "${BUNDLE_DIR}"
fi

if [[ ! -f "${TAR}" ]] && compgen -G "${TAR}.part-*" >/dev/null; then
    cat "${TAR}".part-* > "${TAR}"
fi

verify_sha256_file "${TAR_SUM}" "${BUNDLE_DIR}"
