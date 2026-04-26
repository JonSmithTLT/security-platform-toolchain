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
SKIP_DOCTOR="${SKIP_DOCTOR:-0}"
RESUME_FROM="${RESUME_FROM:-}"
BUILD_JOBS="${BUILD_JOBS:-4}"

IMAGE_TAR="${BUNDLE_DIR}/spt-bundle-${TAG}.tar"
DATA_TAR="${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.tar"
UPLOAD_LIST="${BUNDLE_DIR}/spt-release-${TAG}.upload-assets.txt"
UPLOAD_CMD="${BUNDLE_DIR}/spt-release-${TAG}.gh-upload.sh"
RELEASE_LEDGER="${RELEASE_LEDGER:-artifacts/release-ledger/${TAG}/release-stages.jsonl}"

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
    "preflight doctor"
    "data fetch"
    "data smoke"
    "image build"
    "verify offline"
    "functional smoke"
    "honggfuzz smoke"
    "image bundle"
    "data bundle"
    "data verify"
    "split bundles"
    "verify split bundles"
    "verify data bundle"
    "write upload manifest"
)
TOTAL="${#STEPS[@]}"
CURRENT=0

normalize_resume_from() {
    case "$1" in
        ""|"none")
            printf ''
            ;;
        data-bundle|"data bundle")
            printf 'data bundle'
            ;;
        split|"split bundles")
            printf 'split bundles'
            ;;
        verify|"verify split bundles")
            printf 'verify split bundles'
            ;;
        upload|"write upload manifest")
            printf 'write upload manifest'
            ;;
        *)
            printf 'unknown'
            ;;
    esac
}

stage_rank() {
    case "$1" in
        "preflight doctor") printf 0 ;;
        "data fetch") printf 10 ;;
        "data smoke") printf 20 ;;
        "image build") printf 30 ;;
        "verify offline") printf 40 ;;
        "functional smoke") printf 50 ;;
        "honggfuzz smoke") printf 60 ;;
        "image bundle") printf 70 ;;
        "data bundle") printf 80 ;;
        "data verify") printf 90 ;;
        "split bundles") printf 100 ;;
        "verify split bundles") printf 110 ;;
        "verify data bundle") printf 120 ;;
        "write upload manifest") printf 130 ;;
        *) printf 999 ;;
    esac
}

RESUME_STAGE="$(normalize_resume_from "${RESUME_FROM}")"
if [[ "${RESUME_STAGE}" == "unknown" ]]; then
    printf 'ERROR: unknown RESUME_FROM=%s\n' "${RESUME_FROM}" >&2
    printf 'Valid values: data-bundle, split, verify, upload\n' >&2
    exit 2
fi
RESUME_RANK="$(stage_rank "${RESUME_STAGE}")"

should_skip_for_resume() {
    local stage="$1"
    if [[ -z "${RESUME_STAGE}" ]]; then
        return 1
    fi

    (( $(stage_rank "${stage}") < RESUME_RANK ))
}

utc_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

record_stage() {
    local name="$1"
    local status="$2"
    local started_at="$3"
    local ended_at="$4"
    local command="$5"
    local note="${6:-}"

    mkdir -p "$(dirname "${RELEASE_LEDGER}")"
    python3 - "${RELEASE_LEDGER}" "${TAG}" "${REGISTRY}" "${DATA_DIR}" "${name}" "${status}" "${started_at}" "${ended_at}" "${command}" "${note}" <<'PY'
import json
import sys

ledger, tag, registry, data_dir, name, status, started_at, ended_at, command, note = sys.argv[1:11]
record = {
    "schema_version": "1.0.0",
    "tag": tag,
    "registry": registry,
    "data_dir": data_dir,
    "stage": name,
    "status": status,
    "started_at": started_at,
    "ended_at": ended_at,
    "command": command,
}
if note:
    record["note"] = note

with open(ledger, "a", encoding="utf-8") as fh:
    json.dump(record, fh, sort_keys=True)
    fh.write("\n")
PY
}

run_stage() {
    local name="$1"
    shift
    local started_at ended_at

    log_step "${name}"
    started_at="$(utc_now)"
    if run "$@"; then
        ended_at="$(utc_now)"
        record_stage "${name}" "success" "${started_at}" "${ended_at}" "$*"
    else
        local rc=$?
        ended_at="$(utc_now)"
        record_stage "${name}" "failed" "${started_at}" "${ended_at}" "$*" "exit_code=${rc}"
        return "${rc}"
    fi
}

skip_stage() {
    local name="$1"
    local reason="$2"
    local now

    log_step "${name}"
    log_skip "${reason}"
    now="$(utc_now)"
    record_stage "${name}" "skipped" "${now}" "${now}" "" "${reason}"
}

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
printf 'TAG=%s\nREGISTRY=%s\nDATA_DIR=%s\nSPLIT_SIZE=%s\nBUILD_JOBS=%s\n' "${TAG}" "${REGISTRY}" "${DATA_DIR}" "${SPLIT_SIZE}" "${BUILD_JOBS}"
printf 'RELEASE_LEDGER=%s\n' "${RELEASE_LEDGER}"
if [[ -n "${RESUME_STAGE}" ]]; then
    printf 'RESUME_FROM=%s\n' "${RESUME_STAGE}"
fi

log_step "preflight doctor"
preflight_started="$(utc_now)"
if [[ "${SKIP_DOCTOR}" == "1" ]]; then
    log_skip "preflight doctor"
    preflight_ended="$(utc_now)"
    record_stage "preflight doctor" "skipped" "${preflight_started}" "${preflight_ended}" "" "SKIP_DOCTOR=1"
else
    if BUNDLE_DIR="${BUNDLE_DIR}" DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR}" DATA_DIR="${DATA_DIR}" bash scripts/doctor.sh; then
        preflight_ended="$(utc_now)"
        record_stage "preflight doctor" "success" "${preflight_started}" "${preflight_ended}" "bash scripts/doctor.sh"
    else
        rc=$?
        preflight_ended="$(utc_now)"
        record_stage "preflight doctor" "failed" "${preflight_started}" "${preflight_ended}" "bash scripts/doctor.sh" "exit_code=${rc}"
        exit "${rc}"
    fi
fi

if should_skip_for_resume "data fetch"; then
    skip_stage "data fetch" "RESUME_FROM=${RESUME_STAGE}"
elif [[ "${SKIP_FETCH}" == "1" ]]; then
    skip_stage "data fetch" "SKIP_FETCH=1"
else
    run_stage "data fetch" make data-fetch TAG="${TAG}" DATA_DIR="${DATA_DIR}"
fi

if should_skip_for_resume "data smoke"; then
    skip_stage "data smoke" "RESUME_FROM=${RESUME_STAGE}"
else
    run_stage "data smoke" make data-bundle-smoke TAG="${TAG}" DATA_DIR="${DATA_DIR}"
fi

if should_skip_for_resume "image build"; then
    skip_stage "image build" "RESUME_FROM=${RESUME_STAGE}"
elif [[ "${SKIP_BUILD}" == "1" ]]; then
    skip_stage "image build" "SKIP_BUILD=1"
else
    run_stage "image build" make -j "${BUILD_JOBS}" build-all REGISTRY="${REGISTRY}" TAG="${TAG}"
fi

if should_skip_for_resume "verify offline"; then
    skip_stage "verify offline" "RESUME_FROM=${RESUME_STAGE}"
else
    run_stage "verify offline" make verify-offline REGISTRY="${REGISTRY}" TAG="${TAG}"
fi

if should_skip_for_resume "functional smoke"; then
    skip_stage "functional smoke" "RESUME_FROM=${RESUME_STAGE}"
elif [[ "${SKIP_FUNCTIONAL}" == "1" ]]; then
    skip_stage "functional smoke" "SKIP_FUNCTIONAL=1"
else
    run_stage "functional smoke" make functional-smoke REGISTRY="${REGISTRY}" TAG="${TAG}" DATA_DIR="${DATA_DIR}"
fi

if should_skip_for_resume "honggfuzz smoke"; then
    skip_stage "honggfuzz smoke" "RESUME_FROM=${RESUME_STAGE}"
else
    log_step "honggfuzz smoke"
    honggfuzz_started="$(utc_now)"
    if [[ "${SKIP_HONGGFUZZ}" == "1" ]]; then
        log_skip "SKIP_HONGGFUZZ=1"
        honggfuzz_ended="$(utc_now)"
        record_stage "honggfuzz smoke" "skipped" "${honggfuzz_started}" "${honggfuzz_ended}" "" "SKIP_HONGGFUZZ=1"
    else
        if run make smoke-honggfuzz REGISTRY="${REGISTRY}" TAG="${TAG}"; then
            honggfuzz_ended="$(utc_now)"
            record_stage "honggfuzz smoke" "success" "${honggfuzz_started}" "${honggfuzz_ended}" "make smoke-honggfuzz REGISTRY=${REGISTRY} TAG=${TAG}"
        else
            rc=$?
            honggfuzz_ended="$(utc_now)"
            record_stage "honggfuzz smoke" "non_gating_failed" "${honggfuzz_started}" "${honggfuzz_ended}" "make smoke-honggfuzz REGISTRY=${REGISTRY} TAG=${TAG}" "exit_code=${rc}"
        fi
    fi
fi

if should_skip_for_resume "image bundle"; then
    skip_stage "image bundle" "RESUME_FROM=${RESUME_STAGE}"
elif [[ "${SKIP_BUNDLE}" == "1" ]]; then
    skip_stage "image bundle" "SKIP_BUNDLE=1"
else
    run_stage "image bundle" make bundle-save REGISTRY="${REGISTRY}" TAG="${TAG}" BUNDLE_DIR="${BUNDLE_DIR}"
fi

if should_skip_for_resume "data bundle"; then
    skip_stage "data bundle" "RESUME_FROM=${RESUME_STAGE}"
elif [[ "${SKIP_BUNDLE}" == "1" ]]; then
    skip_stage "data bundle" "SKIP_BUNDLE=1"
else
    run_stage "data bundle" make data-bundle TAG="${TAG}" DATA_DIR="${DATA_DIR}" DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR}"
fi

if should_skip_for_resume "data verify"; then
    skip_stage "data verify" "RESUME_FROM=${RESUME_STAGE}"
elif [[ "${SKIP_BUNDLE}" == "1" ]]; then
    skip_stage "data verify" "SKIP_BUNDLE=1"
else
    run_stage "data verify" make data-verify TAG="${TAG}" DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR}"
fi

if should_skip_for_resume "split bundles"; then
    skip_stage "split bundles" "RESUME_FROM=${RESUME_STAGE}"
else
    log_step "split bundles"
    split_started="$(utc_now)"
    if split_bundle "${IMAGE_TAR}" "${BUNDLE_DIR}/spt-bundle-${TAG}.parts.sha256" \
        && split_bundle "${DATA_TAR}" "${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.parts.sha256"; then
        split_ended="$(utc_now)"
        record_stage "split bundles" "success" "${split_started}" "${split_ended}" "split_bundle image and data bundles"
        log_done "split bundles"
    else
        rc=$?
        split_ended="$(utc_now)"
        record_stage "split bundles" "failed" "${split_started}" "${split_ended}" "split_bundle image and data bundles" "exit_code=${rc}"
        exit "${rc}"
    fi
fi

if should_skip_for_resume "verify split bundles"; then
    skip_stage "verify split bundles" "RESUME_FROM=${RESUME_STAGE}"
else
    run_stage "verify split bundles" env TAG="${TAG}" BUNDLE_DIR="${BUNDLE_DIR}" scripts/verify-image-bundle.sh
fi

if should_skip_for_resume "verify data bundle"; then
    skip_stage "verify data bundle" "RESUME_FROM=${RESUME_STAGE}"
else
    run_stage "verify data bundle" env TAG="${TAG}" DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR}" scripts/verify-data-bundle.sh
fi

log_step "write upload manifest"
upload_started="$(utc_now)"
if write_upload_files; then
    upload_ended="$(utc_now)"
    record_stage "write upload manifest" "success" "${upload_started}" "${upload_ended}" "write_upload_files"
    log_done "upload manifest"
else
    rc=$?
    upload_ended="$(utc_now)"
    record_stage "write upload manifest" "failed" "${upload_started}" "${upload_ended}" "write_upload_files" "exit_code=${rc}"
    exit "${rc}"
fi

printf '\nRelease assets listed in: %s\n' "${UPLOAD_LIST}"
printf 'GitHub upload helper:   %s\n' "${UPLOAD_CMD}"
printf 'Release stage ledger:  %s\n' "${RELEASE_LEDGER}"
printf '\nCreate release if needed:\n'
printf '  gh release create "v%s" --title "SPT offline bundle %s" --notes-file RELEASE_NOTES_0.1.1-smoke.md\n' "${TAG}" "${TAG}"
printf '\nUpload or replace assets:\n'
printf '  %s\n' "${UPLOAD_CMD}"
