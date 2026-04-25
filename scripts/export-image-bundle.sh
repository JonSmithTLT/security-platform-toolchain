#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TAG="${TAG:-latest}"
REGISTRY="${REGISTRY:-registry.internal/security-platform}"
BUNDLE_DIR="${BUNDLE_DIR:-offline-bundles/out}"
SPLIT_SIZE="${SPLIT_SIZE:-1900M}"
TAR="${BUNDLE_DIR}/spt-bundle-${TAG}.tar"

make bundle REGISTRY="${REGISTRY}" TAG="${TAG}"

rm -f "${TAR}.part-"*
split -b "${SPLIT_SIZE}" "${TAR}" "${TAR}.part-"
sha256sum "${TAR}".part-* > "${BUNDLE_DIR}/spt-bundle-${TAG}.parts.sha256"

printf 'Image bundle: %s\n' "${TAR}"
printf 'Image parts checksum: %s\n' "${BUNDLE_DIR}/spt-bundle-${TAG}.parts.sha256"

