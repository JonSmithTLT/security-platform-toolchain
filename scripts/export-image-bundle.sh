#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TAG="${TAG:-latest}"
REGISTRY="${REGISTRY:-registry.internal/security-platform}"
BUNDLE_DIR="${BUNDLE_DIR:-offline-bundles/out}"
SPLIT_SIZE="${SPLIT_SIZE:-1900M}"
TAR="${BUNDLE_DIR}/spt-bundle-${TAG}.tar.gz"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || date +%s)}"

make bundle REGISTRY="${REGISTRY}" TAG="${TAG}" BUNDLE_DIR="${BUNDLE_DIR}" SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}"

PART_SUMS="${BUNDLE_DIR}/spt-bundle-${TAG}.parts.sha256"
rm -f "${TAR}.part-"* "${PART_SUMS}"
split_bytes="$(numfmt --from=iec "${SPLIT_SIZE}")"
tar_bytes="$(stat -c '%s' "${TAR}")"
if (( tar_bytes > split_bytes )); then
    split -b "${SPLIT_SIZE}" "${TAR}" "${TAR}.part-"
    sha256sum "${TAR}".part-* > "${PART_SUMS}"
    printf 'Image parts checksum: %s\n' "${PART_SUMS}"
else
    printf 'Image bundle below SPLIT_SIZE=%s; not splitting\n' "${SPLIT_SIZE}"
fi

printf 'Image bundle: %s\n' "${TAR}"
