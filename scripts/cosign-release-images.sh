#!/usr/bin/env bash
# Sign, verify, or attest SPT release images with cosign.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

ACTION="${1:-}"
REGISTRY="${REGISTRY:-registry.internal/security-platform}"
TAG="${TAG:-latest}"
IMAGES="${IMAGES:-}"
COSIGN_KEY="${COSIGN_KEY:-}"
COSIGN_YES="${COSIGN_YES:-true}"
RELEASE_EVIDENCE_DIR="${RELEASE_EVIDENCE_DIR:-artifacts/release-evidence/${TAG}}"
PROVENANCE_DIR="${RELEASE_EVIDENCE_DIR}/provenance"
SIGNATURE_DIR="${RELEASE_EVIDENCE_DIR}/signatures"

usage() {
    cat >&2 <<'EOF'
Usage: scripts/cosign-release-images.sh sign|verify|attest

Environment:
  REGISTRY, TAG, IMAGES
  COSIGN_KEY              Required key path for sign/verify/attest
  COSIGN_PASSWORD         Passed through to cosign when needed
  RELEASE_EVIDENCE_DIR    Default: artifacts/release-evidence/$TAG
EOF
}

require_cosign() {
    command -v cosign >/dev/null 2>&1 || {
        printf 'ERROR: cosign is required for release image %s\n' "${ACTION}" >&2
        exit 2
    }
    [[ -n "${COSIGN_KEY}" ]] || {
        printf 'ERROR: COSIGN_KEY is required for release image %s\n' "${ACTION}" >&2
        exit 2
    }
    [[ -n "${IMAGES}" ]] || {
        printf 'ERROR: IMAGES is empty\n' >&2
        exit 2
    }
}

image_ref_for() {
    local image="$1"
    printf '%s/spt-%s:%s' "${REGISTRY}" "${image}" "${TAG}"
}

record_jsonl() {
    local path="$1"
    shift
    python3 - "$path" "$@" <<'PY'
import datetime as dt
import json
import sys

path = sys.argv[1]
record = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "image": sys.argv[2],
    "action": sys.argv[3],
    "status": sys.argv[4],
    "command": sys.argv[5],
}
if len(sys.argv) > 6 and sys.argv[6]:
    record["note"] = sys.argv[6]
with open(path, "a", encoding="utf-8") as fh:
    json.dump(record, fh, sort_keys=True)
    fh.write("\n")
PY
}

run_for_images() {
    local events="${SIGNATURE_DIR}/cosign-events.jsonl"
    mkdir -p "${SIGNATURE_DIR}" "${PROVENANCE_DIR}"
    : > "${events}"

    for image in ${IMAGES}; do
        local ref command status note predicate
        local cosign_args=()
        ref="$(image_ref_for "${image}")"
        status="success"
        note=""

        case "${ACTION}" in
            sign)
                command="cosign sign --key ${COSIGN_KEY} ${ref}"
                if [[ "${COSIGN_YES}" == "true" || "${COSIGN_YES}" == "1" ]]; then
                    command="cosign sign --yes --key ${COSIGN_KEY} ${ref}"
                    cosign_args=(--yes)
                else
                    cosign_args=()
                fi
                if ! cosign sign "${cosign_args[@]}" --key "${COSIGN_KEY}" "${ref}"; then
                    status="failed"
                    note="cosign sign failed"
                fi
                ;;
            verify)
                command="cosign verify --key ${COSIGN_KEY} ${ref}"
                if ! cosign verify --key "${COSIGN_KEY}" "${ref}" > "${SIGNATURE_DIR}/spt-${image}.verify.json"; then
                    status="failed"
                    note="cosign verify failed"
                fi
                ;;
            attest)
                predicate="${PROVENANCE_DIR}/spt-${image}.provenance.json"
                command="cosign attest --key ${COSIGN_KEY} --predicate ${predicate} --type slsaprovenance ${ref}"
                if [[ "${COSIGN_YES}" == "true" || "${COSIGN_YES}" == "1" ]]; then
                    command="cosign attest --yes --key ${COSIGN_KEY} --predicate ${predicate} --type slsaprovenance ${ref}"
                    cosign_args=(--yes)
                else
                    cosign_args=()
                fi
                if [[ ! -f "${predicate}" ]]; then
                    status="failed"
                    note="missing provenance predicate: ${predicate}"
                elif ! cosign attest "${cosign_args[@]}" --key "${COSIGN_KEY}" --predicate "${predicate}" --type slsaprovenance "${ref}"; then
                    status="failed"
                    note="cosign attest failed"
                fi
                ;;
        esac

        record_jsonl "${events}" "${ref}" "${ACTION}" "${status}" "${command}" "${note}"
        [[ "${status}" == "success" ]] || return 1
    done
}

case "${ACTION}" in
    sign|verify|attest)
        require_cosign
        run_for_images
        ;;
    *)
        usage
        exit 2
        ;;
esac
