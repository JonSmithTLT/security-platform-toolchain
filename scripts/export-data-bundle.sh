#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TAG="${TAG:-latest}"
DATA_DIR="${DATA_DIR:-data-bundles/sources}"
DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR:-data-bundles/out}"
SPLIT_SIZE="${SPLIT_SIZE:-1900M}"
SANITIZED="${SANITIZED:-false}"
DATA_BUNDLE_NAME="${DATA_BUNDLE_NAME:-spt-data-bundle}"
SKIP_FETCH="${SKIP_FETCH:-0}"
if [[ "${SANITIZED}" == "true" ]]; then
    DATA_BUNDLE_NAME="${DATA_BUNDLE_NAME:-spt-data-sanitized-bundle}"
fi
TAR="${DATA_BUNDLE_DIR}/${DATA_BUNDLE_NAME}-${TAG}.tar"
MANIFEST="${DATA_BUNDLE_DIR}/${DATA_BUNDLE_NAME}-${TAG}.manifest.json"
SOURCE_SUMS="${DATA_BUNDLE_DIR}/${DATA_BUNDLE_NAME}-${TAG}.source-checksums.sha256"

if [[ "${SKIP_FETCH}" != "1" ]]; then
    make data-fetch TAG="${TAG}"
fi

if [[ "${SANITIZED}" == "true" ]]; then
    make data-bundle-sanitized TAG="${TAG}" DATA_DIR="${DATA_DIR}" DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR}"
else
    make data-bundle TAG="${TAG}" DATA_DIR="${DATA_DIR}" DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR}" DATA_BUNDLE_NAME="${DATA_BUNDLE_NAME}"
fi

rm -f "${TAR}.part-"*
split -b "${SPLIT_SIZE}" "${TAR}" "${TAR}.part-"
sha256sum "${TAR}".part-* > "${DATA_BUNDLE_DIR}/${DATA_BUNDLE_NAME}-${TAG}.parts.sha256"

printf 'Data bundle: %s\n' "${TAR}"
printf 'Data manifest: %s\n' "${MANIFEST}"
printf 'Data source checksums: %s\n' "${SOURCE_SUMS}"
