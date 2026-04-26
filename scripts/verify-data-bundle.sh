#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TAG="${TAG:-latest}"
DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR:-data-bundles/out}"
DATA_BUNDLE_NAME="${DATA_BUNDLE_NAME:-spt-data-bundle}"
TAR="${DATA_BUNDLE_DIR}/${DATA_BUNDLE_NAME}-${TAG}.tar"
PART_SUMS="${DATA_BUNDLE_DIR}/${DATA_BUNDLE_NAME}-${TAG}.parts.sha256"
TAR_SUM="${TAR}.sha256"

if [[ -f "${PART_SUMS}" ]]; then
    sha256sum -c "${PART_SUMS}"
fi

if [[ ! -f "${TAR}" ]] && compgen -G "${TAR}.part-*" >/dev/null; then
    cat "${TAR}".part-* > "${TAR}"
fi

sha256sum -c "${TAR_SUM}"

