#!/usr/bin/env bash
# Connected-side release driver for SPT smoke bundles.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TAG="${TAG:-0.1.1-smoke}"
REGISTRY="${REGISTRY:-registry.internal/security-platform}"
DATA_DIR="${DATA_DIR:-data-bundles/sources}"
BUNDLE_DIR="${BUNDLE_DIR:-offline-bundles/out}"
DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR:-data-bundles/out}"
SPLIT_SIZE="${SPLIT_SIZE:-1900M}"
SKIP_FETCH="${SKIP_FETCH:-0}"
SKIP_BUILD="${SKIP_BUILD:-0}"
SKIP_FUNCTIONAL="${SKIP_FUNCTIONAL:-0}"
SKIP_BUNDLE="${SKIP_BUNDLE:-0}"
SKIP_HONGGFUZZ="${SKIP_HONGGFUZZ:-0}"

IMAGE_TAR="${BUNDLE_DIR}/spt-bundle-${TAG}.tar"
DATA_TAR="${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.tar"
UPLOAD_LIST="${BUNDLE_DIR}/spt-release-${TAG}.upload-assets.txt"
UPLOAD_CMD="${BUNDLE_DIR}/spt-release-${TAG}.gh-upload.sh"

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
    "data fetch"
    "data smoke"
    "image build"
    "verify offline"
    "functional smoke"
    "honggfuzz smoke"
    "image bundle"
    "data bundle"
    "split bundles"
    "verify split bundles"
    "write upload manifest"
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

split_bundle() {
    local tar_path="$1"
    local parts_sum="$2"
    rm -f "${tar_path}.part-"* "${parts_sum}"
    split -b "${SPLIT_SIZE}" "${tar_path}" "${tar_path}.part-"
    sha256sum "${tar_path}".part-* > "${parts_sum}"
}

write_upload_files() {
    mkdir -p "${BUNDLE_DIR}" "${DATA_BUNDLE_DIR}"
    : > "${UPLOAD_LIST}"

    for path in \
        "${IMAGE_TAR}".part-* \
        "${BUNDLE_DIR}/spt-bundle-${TAG}.parts.sha256" \
        "${IMAGE_TAR}.sha256" \
        "${BUNDLE_DIR}/spt-bundle-${TAG}.manifest.json" \
        "${DATA_TAR}".part-* \
        "${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.parts.sha256" \
        "${DATA_TAR}.sha256" \
        "${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.manifest.json" \
        "${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.source-checksums.sha256" \
        RELEASE_CHECKLIST.md \
        RELEASE_NOTES_0.1.1-smoke.md \
        KNOWN_LIMITATIONS.md \
        SECURITY_NOTES.md; do
        if [[ -e "${path}" ]]; then
            printf '%s\n' "${path}" >> "${UPLOAD_LIST}"
        fi
    done

    cat > "${UPLOAD_CMD}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
gh release upload "v${TAG}" \\
$(sed 's/^/  /; s/$/ \\/' "${UPLOAD_LIST}")
  --clobber
EOF
    chmod +x "${UPLOAD_CMD}"
}

printf '%sSPT release driver%s\n' "${BOLD}" "${RESET}"
printf 'TAG=%s\nREGISTRY=%s\nDATA_DIR=%s\nSPLIT_SIZE=%s\n' "${TAG}" "${REGISTRY}" "${DATA_DIR}" "${SPLIT_SIZE}"

log_step "data fetch"
if [[ "${SKIP_FETCH}" == "1" ]]; then
    log_skip "data fetch"
else
    run make data-fetch TAG="${TAG}" DATA_DIR="${DATA_DIR}"
fi

log_step "data smoke"
run make data-bundle-smoke TAG="${TAG}" DATA_DIR="${DATA_DIR}"

log_step "image build"
if [[ "${SKIP_BUILD}" == "1" ]]; then
    log_skip "image build"
else
    run make build-all REGISTRY="${REGISTRY}" TAG="${TAG}"
fi

log_step "verify offline"
run make verify-offline REGISTRY="${REGISTRY}" TAG="${TAG}"

log_step "functional smoke"
if [[ "${SKIP_FUNCTIONAL}" == "1" ]]; then
    log_skip "functional smoke"
else
    run make functional-smoke REGISTRY="${REGISTRY}" TAG="${TAG}" DATA_DIR="${DATA_DIR}"
fi

log_step "honggfuzz smoke"
if [[ "${SKIP_HONGGFUZZ}" == "1" ]]; then
    log_skip "honggfuzz smoke"
else
    run make smoke-honggfuzz REGISTRY="${REGISTRY}" TAG="${TAG}" || true
fi

log_step "image bundle"
if [[ "${SKIP_BUNDLE}" == "1" ]]; then
    log_skip "image bundle"
else
    run make bundle-save REGISTRY="${REGISTRY}" TAG="${TAG}" BUNDLE_DIR="${BUNDLE_DIR}"
fi

log_step "data bundle"
if [[ "${SKIP_BUNDLE}" == "1" ]]; then
    log_skip "data bundle"
else
    run make data-bundle TAG="${TAG}" DATA_DIR="${DATA_DIR}" DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR}"
    run make data-verify TAG="${TAG}" DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR}"
fi

log_step "split bundles"
split_bundle "${IMAGE_TAR}" "${BUNDLE_DIR}/spt-bundle-${TAG}.parts.sha256"
split_bundle "${DATA_TAR}" "${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.parts.sha256"
log_done "split bundles"

log_step "verify split bundles"
run env TAG="${TAG}" BUNDLE_DIR="${BUNDLE_DIR}" scripts/verify-image-bundle.sh
run env TAG="${TAG}" DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR}" scripts/verify-data-bundle.sh

log_step "write upload manifest"
write_upload_files
log_done "upload manifest"

printf '\nRelease assets listed in: %s\n' "${UPLOAD_LIST}"
printf 'GitHub upload helper:   %s\n' "${UPLOAD_CMD}"
printf '\nCreate release if needed:\n'
printf '  gh release create "v%s" --title "SPT offline bundle %s" --notes-file RELEASE_NOTES_0.1.1-smoke.md\n' "${TAG}" "${TAG}"
printf '\nUpload or replace assets:\n'
printf '  %s\n' "${UPLOAD_CMD}"
