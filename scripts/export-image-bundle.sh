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

make bundle REGISTRY="${REGISTRY}" TAG="${TAG}" SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}"

rm -f "${TAR}.part-"*
split -b "${SPLIT_SIZE}" "${TAR}" "${TAR}.part-"
sha256sum "${TAR}".part-* > "${BUNDLE_DIR}/spt-bundle-${TAG}.parts.sha256"

printf 'Image bundle: %s\n' "${TAR}"
printf 'Image parts checksum: %s\n' "${BUNDLE_DIR}/spt-bundle-${TAG}.parts.sha256"
