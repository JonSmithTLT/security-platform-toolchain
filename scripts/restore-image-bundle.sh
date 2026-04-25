#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TAG="${TAG:-latest}"
REGISTRY="${REGISTRY:-registry.internal/security-platform}"
BUNDLE_DIR="${BUNDLE_DIR:-offline-bundles/out}"
TAR="${BUNDLE_DIR}/spt-bundle-${TAG}.tar"

"${ROOT_DIR}/scripts/verify-image-bundle.sh"
docker load -i "${TAR}"

printf 'Loaded SPT image tags:\n'
docker images --format '{{.Repository}}:{{.Tag}}' | grep "/spt-.*:${TAG}$" | sort || true

make verify-offline REGISTRY="${REGISTRY}" TAG="${TAG}"

