#!/usr/bin/env bash
# Restore-side release driver for SPT split image/data bundles.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TAG="${TAG:-0.1.1-smoke}"
REGISTRY="${REGISTRY:-registry.internal/security-platform}"
BUNDLE_DIR="${BUNDLE_DIR:-offline-bundles/out}"
DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR:-data-bundles/out}"
RESTORE_DIR="${RESTORE_DIR:-artifacts/release-restore/${TAG}}"
RESTORED_DATA_DIR="${RESTORED_DATA_DIR:-${RESTORE_DIR}/spt-data}"
SKIP_DOCKER_LOAD="${SKIP_DOCKER_LOAD:-0}"
SKIP_VERIFY_OFFLINE="${SKIP_VERIFY_OFFLINE:-0}"
SKIP_DATA_EXTRACT="${SKIP_DATA_EXTRACT:-0}"
RUN_FUNCTIONAL="${RUN_FUNCTIONAL:-0}"

IMAGE_TAR="${BUNDLE_DIR}/spt-bundle-${TAG}.tar"
DATA_TAR="${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.tar"

if [[ -t 1 ]]; then
    BOLD="$(printf '\033[1m')"
    GREEN="$(printf '\033[32m')"
    YELLOW="$(printf '\033[33m')"
    RESET="$(printf '\033[0m')"
else
    BOLD=""
    GREEN=""
    YELLOW=""
    RESET=""
fi

STEPS=(
    "verify image parts"
    "load image bundle"
    "verify offline"
    "verify data parts"
    "extract data bundle"
    "data bundle smoke"
    "optional functional smoke"
)
TOTAL="${#STEPS[@]}"
CURRENT=0

log_step() {
    CURRENT=$((CURRENT + 1))
    printf '\n%s[%02d/%02d] %s%s\n' "${BOLD}" "${CURRENT}" "${TOTAL}" "$1" "${RESET}"
}

log_skip() {
    printf '%sSKIP:%s %s\n' "${YELLOW}" "${RESET}" "$1"
}

log_done() {
    printf '%sDONE:%s %s\n' "${GREEN}" "${RESET}" "$1"
}

run() {
    printf '+ %s\n' "$*"
    "$@"
}

printf '%sSPT restore driver%s\n' "${BOLD}" "${RESET}"
printf 'TAG=%s\nREGISTRY=%s\nBUNDLE_DIR=%s\nDATA_BUNDLE_DIR=%s\nRESTORE_DIR=%s\n' \
    "${TAG}" "${REGISTRY}" "${BUNDLE_DIR}" "${DATA_BUNDLE_DIR}" "${RESTORE_DIR}"

mkdir -p "${RESTORE_DIR}"

log_step "verify image parts"
run env TAG="${TAG}" BUNDLE_DIR="${BUNDLE_DIR}" scripts/verify-image-bundle.sh

log_step "load image bundle"
if [[ "${SKIP_DOCKER_LOAD}" == "1" ]]; then
    log_skip "docker load"
else
    run docker load -i "${IMAGE_TAR}"
    printf 'Loaded SPT image tags:\n'
    docker images --format '{{.Repository}}:{{.Tag}}' | grep "/spt-.*:${TAG}$" | sort || true
fi

log_step "verify offline"
if [[ "${SKIP_VERIFY_OFFLINE}" == "1" ]]; then
    log_skip "verify offline"
else
    run make verify-offline REGISTRY="${REGISTRY}" TAG="${TAG}"
fi

log_step "verify data parts"
run env TAG="${TAG}" DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR}" scripts/verify-data-bundle.sh

log_step "extract data bundle"
if [[ "${SKIP_DATA_EXTRACT}" == "1" ]]; then
    log_skip "data extract"
else
    rm -rf "${RESTORED_DATA_DIR}"
    mkdir -p "${RESTORED_DATA_DIR}"
    run tar -xf "${DATA_TAR}" -C "${RESTORED_DATA_DIR}"
fi

DATA_SMOKE_DIR="${RESTORED_DATA_DIR}/sources"

log_step "data bundle smoke"
run make data-bundle-smoke DATA_DIR="${DATA_SMOKE_DIR}"

log_step "optional functional smoke"
if [[ "${RUN_FUNCTIONAL}" == "1" ]]; then
    run make functional-smoke REGISTRY="${REGISTRY}" TAG="${TAG}" DATA_DIR="${DATA_SMOKE_DIR}"
else
    log_skip "functional smoke (set RUN_FUNCTIONAL=1 to enable)"
fi

log_done "restore validation complete"
printf '\nRestored data dir: %s\n' "${DATA_SMOKE_DIR}"
