#!/usr/bin/env bash
# Sign the data bundle manifest with a detached GPG signature.

set -euo pipefail

TAG="${TAG:-latest}"
DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR:-data-bundles/out}"
DATA_BUNDLE_NAME="${DATA_BUNDLE_NAME:-spt-data-bundle}"
MANIFEST="${DATA_MANIFEST:-${DATA_BUNDLE_DIR}/${DATA_BUNDLE_NAME}-${TAG}.manifest.json}"
SIGNATURE="${DATA_SIGNATURE:-${MANIFEST}.asc}"
GPG_KEY="${GPG_KEY:-}"
VERIFY_ONLY="${VERIFY_ONLY:-0}"

if [[ ! -f "${MANIFEST}" ]]; then
    printf 'ERROR: data bundle manifest not found: %s\n' "${MANIFEST}" >&2
    exit 2
fi

command -v gpg >/dev/null 2>&1 || {
    printf 'ERROR: gpg is required for data bundle signing\n' >&2
    exit 2
}

if [[ "${VERIFY_ONLY}" == "1" ]]; then
    gpg --verify "${SIGNATURE}" "${MANIFEST}"
    exit 0
fi

gpg_args=(--batch --yes --armor --detach-sign --output "${SIGNATURE}")
if [[ -n "${GPG_KEY}" ]]; then
    gpg_args+=(--local-user "${GPG_KEY}")
fi
gpg "${gpg_args[@]}" "${MANIFEST}"
sha256sum "${SIGNATURE}" > "${SIGNATURE}.sha256"

printf 'Data manifest signature: %s\n' "${SIGNATURE}"
printf 'Signature checksum: %s.sha256\n' "${SIGNATURE}"
