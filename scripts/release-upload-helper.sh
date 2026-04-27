#!/usr/bin/env bash
# Create/update a GitHub release and upload assets from the generated manifest.

set -euo pipefail

TAG="${TAG:-latest}"
BUNDLE_DIR="${BUNDLE_DIR:-offline-bundles/out}"
UPLOAD_LIST="${UPLOAD_LIST:-${BUNDLE_DIR}/spt-release-${TAG}.upload-assets.txt}"
RELEASE_TAG="${RELEASE_TAG:-v${TAG}}"
RELEASE_TITLE="${RELEASE_TITLE:-SPT offline bundle ${TAG}}"
RELEASE_NOTES="${RELEASE_NOTES:-RELEASE_NOTES_${TAG}.md}"
DRY_RUN="${DRY_RUN:-0}"

if [[ ! -f "${UPLOAD_LIST}" ]]; then
    printf 'ERROR: upload asset list not found: %s\n' "${UPLOAD_LIST}" >&2
    exit 2
fi

notes_arg=()
if [[ -f "${RELEASE_NOTES}" ]]; then
    notes_arg=(--notes-file "${RELEASE_NOTES}")
else
    notes_arg=(--notes "SPT offline bundle ${TAG}")
fi

assets=()
while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    if [[ -e "${path}" ]]; then
        assets+=("${path}")
    else
        printf 'WARN: upload asset missing, skipping: %s\n' "${path}" >&2
    fi
done < "${UPLOAD_LIST}"

if [[ "${#assets[@]}" -eq 0 ]]; then
    printf 'ERROR: no upload assets found from %s\n' "${UPLOAD_LIST}" >&2
    exit 2
fi

run() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    if [[ "${DRY_RUN}" != "1" ]]; then
        "$@"
    fi
}

if [[ "${DRY_RUN}" != "1" ]]; then
    command -v gh >/dev/null 2>&1 || {
        printf 'ERROR: gh is required for release upload\n' >&2
        exit 2
    }
fi

if [[ "${DRY_RUN}" == "1" ]]; then
    printf 'DRY RUN: would create/update release %s and upload %d assets\n' "${RELEASE_TAG}" "${#assets[@]}"
elif gh release view "${RELEASE_TAG}" >/dev/null 2>&1; then
    run gh release edit "${RELEASE_TAG}" --title "${RELEASE_TITLE}" "${notes_arg[@]}"
else
    run gh release create "${RELEASE_TAG}" --title "${RELEASE_TITLE}" "${notes_arg[@]}"
fi

run gh release upload "${RELEASE_TAG}" "${assets[@]}" --clobber
