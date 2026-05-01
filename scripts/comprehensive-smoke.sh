#!/usr/bin/env bash
# Run a broad post-build/post-release health check and write a compact report.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TAG="${TAG:-latest}"
REGISTRY="${REGISTRY:-registry.internal/security-platform}"
DATA_DIR="${DATA_DIR:-data-bundles/sources}"
BUNDLE_DIR="${BUNDLE_DIR:-offline-bundles/out}"
DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR:-data-bundles/out}"
OUT_DIR="${OUT_DIR:-artifacts/comprehensive-smoke/${TAG}}"
ASSET_MAX_BYTES="${ASSET_MAX_BYTES:-2147483648}"
RUN_FUNCTIONAL="${RUN_FUNCTIONAL:-1}"
RUN_WHEELHOUSE_SMOKE="${RUN_WHEELHOUSE_SMOKE:-1}"
RUN_FRONTEND_NPM_SMOKE="${RUN_FRONTEND_NPM_SMOKE:-1}"
RUN_RESTORE="${RUN_RESTORE:-0}"

JSONL="${OUT_DIR}/comprehensive-smoke.jsonl"
MARKDOWN="${OUT_DIR}/comprehensive-smoke.md"

mkdir -p "${OUT_DIR}"
: > "${JSONL}"

utc_now() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

record() {
    local name="$1"
    local status="$2"
    local note="${3:-}"
    python3 - "${JSONL}" "${name}" "${status}" "${note}" <<'PY'
import json
import sys

path, name, status, note = sys.argv[1:5]
record = {
    "name": name,
    "status": status,
}
if note:
    record["note"] = note
with open(path, "a", encoding="utf-8") as fh:
    json.dump(record, fh, sort_keys=True)
    fh.write("\n")
PY
}

run_step() {
    local name="$1"
    shift
    printf '\n==> %s\n' "${name}"
    printf '  $ %s\n' "$*"
    if "$@"; then
        record "${name}" "pass"
    else
        local rc=$?
        record "${name}" "fail" "exit_code=${rc}"
        return "${rc}"
    fi
}

skip_step() {
    local name="$1"
    local reason="$2"
    printf '\n==> %s\n' "${name}"
    printf 'SKIP: %s\n' "${reason}"
    record "${name}" "skip" "${reason}"
}

check_shell_syntax() {
    mapfile -t scripts < <(find scripts data-bundles/fetch examples -type f -name '*.sh' | sort)
    bash -n "${scripts[@]}"
}

check_release_assets() {
    local upload_list="${BUNDLE_DIR}/spt-release-${TAG}.upload-assets.txt"
    local missing=0 oversized=0 stale_parts=0 asset size tar_path parts_glob

    [[ -f "${upload_list}" ]] || {
        printf 'missing upload asset list: %s\n' "${upload_list}" >&2
        return 1
    }

    while IFS= read -r asset; do
        [[ -n "${asset}" ]] || continue
        if [[ ! -f "${asset}" ]]; then
            printf 'missing upload asset: %s\n' "${asset}" >&2
            missing=$((missing + 1))
            continue
        fi
        size="$(stat -c '%s' "${asset}")"
        if (( size > ASSET_MAX_BYTES )); then
            printf 'oversized upload asset (%s bytes): %s\n' "${size}" "${asset}" >&2
            oversized=$((oversized + 1))
        fi
    done < "${upload_list}"

    for tar_path in \
        "${BUNDLE_DIR}/spt-bundle-${TAG}.tar.gz" \
        "${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.tar.gz"; do
        [[ -f "${tar_path}" ]] || continue
        size="$(stat -c '%s' "${tar_path}")"
        parts_glob="${tar_path}.part-*"
        if (( size <= ASSET_MAX_BYTES )) && compgen -G "${parts_glob}" >/dev/null; then
            printf 'unnecessary split parts for sub-limit tarball: %s (%s bytes)\n' "${tar_path}" "${size}" >&2
            stale_parts=$((stale_parts + 1))
        fi
    done

    (( missing == 0 && oversized == 0 && stale_parts == 0 ))
}

write_report() {
    python3 - "${JSONL}" "${MARKDOWN}" "${TAG}" "$(utc_now)" <<'PY'
import json
import sys

jsonl, markdown, tag, generated_at = sys.argv[1:5]
records = []
with open(jsonl, "r", encoding="utf-8") as fh:
    for line in fh:
        if line.strip():
            records.append(json.loads(line))

counts = {"pass": 0, "fail": 0, "skip": 0}
for record in records:
    counts[record["status"]] = counts.get(record["status"], 0) + 1

with open(markdown, "w", encoding="utf-8") as fh:
    fh.write(f"# Comprehensive Smoke: {tag}\n\n")
    fh.write(f"- Generated: {generated_at}\n")
    fh.write(f"- Passed: {counts.get('pass', 0)}\n")
    fh.write(f"- Failed: {counts.get('fail', 0)}\n")
    fh.write(f"- Skipped: {counts.get('skip', 0)}\n\n")
    fh.write("| Check | Status | Note |\n")
    fh.write("|---|---:|---|\n")
    for record in records:
        fh.write(
            f"| {record['name']} | {record['status']} | "
            f"{record.get('note', '')} |\n"
        )

print(f"Comprehensive smoke report: {markdown}")
print(f"Comprehensive smoke records: {jsonl}")
if counts.get("fail", 0):
    sys.exit(1)
PY
}

main() {
    printf 'SPT comprehensive smoke\n'
    printf 'TAG=%s\n' "${TAG}"
    printf 'REGISTRY=%s\n' "${REGISTRY}"
    printf 'DATA_DIR=%s\n' "${DATA_DIR}"
    printf 'OUT_DIR=%s\n' "${OUT_DIR}"

    run_step "shell syntax" check_shell_syntax
    run_step "doctor" make doctor REGISTRY="${REGISTRY}" TAG="${TAG}" DATA_DIR="${DATA_DIR}"
    run_step "data bundle smoke" make data-bundle-smoke TAG="${TAG}" DATA_DIR="${DATA_DIR}"

    if [[ -f "${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.tar.gz.sha256" ]]; then
        run_step "verify data bundle" env TAG="${TAG}" DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR}" scripts/verify-data-bundle.sh
    else
        skip_step "verify data bundle" "data bundle checksum not found"
    fi

    if [[ -f "${BUNDLE_DIR}/spt-bundle-${TAG}.tar.gz.sha256" ]]; then
        run_step "verify image bundle" env TAG="${TAG}" BUNDLE_DIR="${BUNDLE_DIR}" scripts/verify-image-bundle.sh
    else
        skip_step "verify image bundle" "image bundle checksum not found"
    fi

    if [[ -f "${BUNDLE_DIR}/spt-release-${TAG}.upload-assets.txt" ]]; then
        run_step "release asset manifest" check_release_assets
    else
        skip_step "release asset manifest" "upload asset list not found"
    fi

    run_step "verify offline" make verify-offline REGISTRY="${REGISTRY}" TAG="${TAG}"
    run_step "container structure" make container-structure-test REGISTRY="${REGISTRY}" TAG="${TAG}"
    run_step "pipeline playbooks" make pipeline-playbooks-validate

    if [[ -f "data-bundles/out/spt-cve-index.sqlite" ]]; then
        run_step "cve index smoke" make cve-index-smoke
    else
        skip_step "cve index smoke" "data-bundles/out/spt-cve-index.sqlite not found"
    fi

    if [[ "${RUN_WHEELHOUSE_SMOKE}" == "1" ]]; then
        run_step "python wheelhouse verify" make python-wheelhouse-verify DATA_DIR="${DATA_DIR}"
        run_step "python wheelhouse smoke" make python-wheelhouse-smoke REGISTRY="${REGISTRY}" TAG="${TAG}"
    else
        skip_step "python wheelhouse smoke" "RUN_WHEELHOUSE_SMOKE=0"
    fi

    if [[ "${RUN_FRONTEND_NPM_SMOKE}" == "1" ]]; then
        run_step "frontend npm verify" make frontend-npm-verify DATA_DIR="${DATA_DIR}"
        run_step "frontend npm smoke" make frontend-npm-smoke REGISTRY="${REGISTRY}" TAG="${TAG}"
    else
        skip_step "frontend npm smoke" "RUN_FRONTEND_NPM_SMOKE=0"
    fi

    if [[ "${RUN_FUNCTIONAL}" == "1" ]]; then
        run_step "functional smoke" make functional-smoke REGISTRY="${REGISTRY}" TAG="${TAG}" DATA_DIR="${DATA_DIR}"
    else
        skip_step "functional smoke" "RUN_FUNCTIONAL=0"
    fi

    run_step "release policy" make release-policy-check REGISTRY="${REGISTRY}" TAG="${TAG}"

    if [[ "${RUN_RESTORE}" == "1" ]]; then
        run_step "restore validation" make release-restore REGISTRY="${REGISTRY}" TAG="${TAG}" RUN_FUNCTIONAL=1
    else
        skip_step "restore validation" "RUN_RESTORE=0"
    fi

    write_report
}

main "$@"
