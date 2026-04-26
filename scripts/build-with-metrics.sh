#!/usr/bin/env bash
# Build SPT images one by one and capture timing/size metrics.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

REGISTRY="${REGISTRY:-registry.internal/security-platform}"
TAG="${TAG:-latest}"
IMAGES="${IMAGES:-}"
OUT_DIR="${BUILD_METRICS_DIR:-artifacts/build-metrics}"
JSONL="${OUT_DIR}/build-report-${TAG}.jsonl"
MARKDOWN="${OUT_DIR}/build-report-${TAG}.md"
KEEP_GOING="${KEEP_GOING:-0}"

if [[ -z "${IMAGES}" ]]; then
    printf 'ERROR: IMAGES is empty. Run through make build-report.\n' >&2
    exit 1
fi

mkdir -p "${OUT_DIR}"
: > "${JSONL}"

utc_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

append_record() {
    local image="$1"
    local status="$2"
    local started_at="$3"
    local ended_at="$4"
    local duration_seconds="$5"
    local size="$6"
    local exit_code="$7"

    python3 - "${JSONL}" "${REGISTRY}" "${TAG}" "${image}" "${status}" "${started_at}" "${ended_at}" "${duration_seconds}" "${size}" "${exit_code}" <<'PY'
import json
import sys

jsonl, registry, tag, image, status, started_at, ended_at, duration_seconds, size, exit_code = sys.argv[1:11]
record = {
    "schema_version": "1.0.0",
    "registry": registry,
    "tag": tag,
    "image": image,
    "image_ref": f"{registry}/spt-{image}:{tag}",
    "status": status,
    "started_at": started_at,
    "ended_at": ended_at,
    "duration_seconds": int(duration_seconds),
    "size": size,
    "exit_code": int(exit_code),
}
with open(jsonl, "a", encoding="utf-8") as fh:
    json.dump(record, fh, sort_keys=True)
    fh.write("\n")
PY
}

write_markdown() {
    python3 - "${JSONL}" "${MARKDOWN}" "${REGISTRY}" "${TAG}" <<'PY'
import json
import sys

jsonl, markdown, registry, tag = sys.argv[1:5]
records = []
with open(jsonl, "r", encoding="utf-8") as fh:
    for line in fh:
        if line.strip():
            records.append(json.loads(line))

records.sort(key=lambda item: item["duration_seconds"], reverse=True)

with open(markdown, "w", encoding="utf-8") as fh:
    fh.write(f"# SPT Build Report\n\n")
    fh.write(f"- Registry: `{registry}`\n")
    fh.write(f"- Tag: `{tag}`\n")
    fh.write(f"- Images: {len(records)}\n\n")
    fh.write("| Image | Status | Duration | Size |\n")
    fh.write("|---|---:|---:|---:|\n")
    for record in records:
        fh.write(
            f"| `spt-{record['image']}` | {record['status']} | "
            f"{record['duration_seconds']}s | {record['size']} |\n"
        )
PY
}

printf 'SPT build metrics\n'
printf 'REGISTRY=%s\nTAG=%s\nOUT_DIR=%s\n\n' "${REGISTRY}" "${TAG}" "${OUT_DIR}"

failed=0
for image in ${IMAGES}; do
    image_ref="${REGISTRY}/spt-${image}:${TAG}"
    printf '\n==> Building %s\n' "${image_ref}"

    started_at="$(utc_now)"
    start_epoch="$(date +%s)"
    status="success"
    exit_code=0

    set +e
    make "${image}" REGISTRY="${REGISTRY}" TAG="${TAG}"
    exit_code=$?
    set -e

    if (( exit_code != 0 )); then
        status="failed"
        failed=1
    fi

    end_epoch="$(date +%s)"
    ended_at="$(utc_now)"
    duration_seconds=$((end_epoch - start_epoch))
    size="$(docker images --format '{{.Size}}' "${image_ref}" 2>/dev/null || true)"
    if [[ -z "${size}" ]]; then
        size="(not built)"
    fi

    append_record "${image}" "${status}" "${started_at}" "${ended_at}" "${duration_seconds}" "${size}" "${exit_code}"
    write_markdown

    if [[ "${status}" == "failed" && "${KEEP_GOING}" != "1" ]]; then
        printf 'ERROR: build failed for %s. Report: %s\n' "${image}" "${MARKDOWN}" >&2
        exit "${exit_code}"
    fi
done

printf '\nBuild metrics written:\n'
printf '  %s\n' "${JSONL}"
printf '  %s\n' "${MARKDOWN}"

if (( failed > 0 )); then
    exit 1
fi
