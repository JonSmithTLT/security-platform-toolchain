#!/usr/bin/env bash
# Collect platform self-scan evidence for a release candidate.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

REGISTRY="${REGISTRY:-registry.internal/security-platform}"
TAG="${TAG:-latest}"
IMAGES="${IMAGES:-}"
OUT_DIR="${RELEASE_EVIDENCE_DIR:-artifacts/release-evidence/${TAG}}"
STRICT_RELEASE_EVIDENCE="${STRICT_RELEASE_EVIDENCE:-0}"
OSV_DB_DIR="${OSV_DB_DIR:-data-bundles/sources/osv}"

if [[ -z "${IMAGES}" ]]; then
    printf 'ERROR: IMAGES is empty. Run through make release-evidence.\n' >&2
    exit 1
fi

mkdir -p "${OUT_DIR}/images" "${OUT_DIR}/repo" "${OUT_DIR}/reports"

events_file="${OUT_DIR}/release-evidence-events.jsonl"
: > "${events_file}"

record_event() {
    local name="$1"
    local status="$2"
    local command="$3"
    local note="${4:-}"

    python3 - "${events_file}" "${name}" "${status}" "${command}" "${note}" <<'PY'
import datetime as dt
import json
import sys

events_file, name, status, command, note = sys.argv[1:6]
record = {
    "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "name": name,
    "status": status,
    "command": command,
}
if note:
    record["note"] = note
with open(events_file, "a", encoding="utf-8") as fh:
    json.dump(record, fh, sort_keys=True)
    fh.write("\n")
PY
}

run_evidence() {
    local name="$1"
    shift
    local command="$*"

    printf '==> %s\n' "${name}"
    set +e
    "$@"
    local rc=$?
    set -e

    if (( rc == 0 )); then
        record_event "${name}" "success" "${command}"
    else
        record_event "${name}" "failed" "${command}" "exit_code=${rc}"
        if [[ "${STRICT_RELEASE_EVIDENCE}" == "1" ]]; then
            return "${rc}"
        fi
    fi
}

docker_sock_args=()
if [[ -S /var/run/docker.sock ]]; then
    docker_sock_args=(-v /var/run/docker.sock:/var/run/docker.sock)
fi

printf 'SPT release evidence collector\n'
printf 'REGISTRY=%s\nTAG=%s\nOUT_DIR=%s\n\n' "${REGISTRY}" "${TAG}" "${OUT_DIR}"

run_evidence "image size table" \
    sh -lc "make image-sizes REGISTRY='${REGISTRY}' TAG='${TAG}' > '${OUT_DIR}/reports/image-sizes.md'"

run_evidence "declared tool versions" \
    sh -lc "make tool-versions-declared REGISTRY='${REGISTRY}' TAG='${TAG}' > '${OUT_DIR}/reports/tool-versions-declared.md'"

run_evidence "installed tool versions" \
    sh -lc "TOOL_INVENTORY_DIR='${OUT_DIR}/tool-inventory' make tool-versions-installed REGISTRY='${REGISTRY}' TAG='${TAG}'"

run_evidence "tool drift check" \
    sh -lc "TOOL_INVENTORY_DIR='${OUT_DIR}/tool-inventory' make tool-drift-check REGISTRY='${REGISTRY}' TAG='${TAG}'"

for image in ${IMAGES}; do
    image_ref="${REGISTRY}/spt-${image}:${TAG}"
    safe_image="spt-${image}"
    image_dir="${OUT_DIR}/images/${safe_image}"
    mkdir -p "${image_dir}/inspect" "${image_dir}/sbom" "${image_dir}/grype"

    run_evidence "inspect ${safe_image}" \
        sh -lc "docker image inspect '${image_ref}' > '${image_dir}/inspect/image-inspect.json'"

    run_evidence "metadata contract ${safe_image}" \
        python3 - "${image_dir}/inspect/image-inspect.json" <<'PY'
import json
import sys

required = [
    "org.opencontainers.image.source",
    "org.opencontainers.image.revision",
    "org.opencontainers.image.version",
    "org.opencontainers.image.created",
    "org.opencontainers.image.licenses",
    "org.security-platform-toolchain.schema-version",
]
data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
labels = data[0].get("Config", {}).get("Labels", {}) or {}
missing = [key for key in required if not labels.get(key)]
if missing:
    raise SystemExit(f"missing required labels: {', '.join(missing)}")
PY

    run_evidence "sbom ${safe_image}" \
        docker run --rm "${docker_sock_args[@]}" \
            -e TARGET_REPO="${image_ref}" \
            -e SBOM_FORMAT=cyclonedx-json \
            -e ARTIFACTS_DIR=/artifacts \
            -v "${ROOT_DIR}/${image_dir}/sbom:/artifacts" \
            "${REGISTRY}/spt-sbom:${TAG}"

    run_evidence "grype ${safe_image}" \
        docker run --rm "${docker_sock_args[@]}" \
            -e IMAGE_SCAN_TARGET="${image_ref}" \
            -e ARTIFACTS_DIR=/artifacts \
            -v "${ROOT_DIR}/${image_dir}/grype:/artifacts" \
            "${REGISTRY}/spt-image-scanner:${TAG}"
done

run_evidence "secret scan repository" \
    docker run --rm \
        -e TARGET_REPO=/workspace \
        -e ARTIFACTS_DIR=/artifacts \
        -v "${ROOT_DIR}:/workspace:ro" \
        -v "${ROOT_DIR}/${OUT_DIR}/repo/secrets:/artifacts" \
        "${REGISTRY}/spt-secrets:${TAG}"

if [[ -d "${OSV_DB_DIR}" ]]; then
    run_evidence "osv scan repository" \
        docker run --rm --network none \
            -e TARGET_REPO=/workspace \
            -e ARTIFACTS_DIR=/artifacts \
            -e OSV_OFFLINE=1 \
            -e OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY=/osv-db \
            -v "${ROOT_DIR}:/workspace:ro" \
            -v "${ROOT_DIR}/${OSV_DB_DIR}:/osv-db:ro" \
            -v "${ROOT_DIR}/${OUT_DIR}/repo/osv-scanner:/artifacts" \
            "${REGISTRY}/spt-osv-scanner:${TAG}"
else
    record_event "osv scan repository" "skipped" "" "missing OSV_DB_DIR=${OSV_DB_DIR}"
fi

run_evidence "release evidence artifact manifest" \
    python3 common/emit-artifact-manifest.py \
        --artifacts-dir "${OUT_DIR}" \
        --output "${OUT_DIR}/manifest.json" \
        --job-id "release-evidence-${TAG}"

python3 - "${OUT_DIR}" "${REGISTRY}" "${TAG}" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
registry = sys.argv[2]
tag = sys.argv[3]
events_path = out_dir / "release-evidence-events.jsonl"
events = [json.loads(line) for line in events_path.read_text(encoding="utf-8").splitlines() if line.strip()]
failed = [event for event in events if event["status"] == "failed"]
skipped = [event for event in events if event["status"] == "skipped"]

summary = {
    "schema_version": "1.0.0",
    "registry": registry,
    "tag": tag,
    "event_count": len(events),
    "failed_count": len(failed),
    "skipped_count": len(skipped),
}
(out_dir / "release-evidence-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

with (out_dir / "release-evidence-summary.md").open("w", encoding="utf-8") as fh:
    fh.write("# Release Evidence Summary\n\n")
    fh.write(f"- Registry: `{registry}`\n")
    fh.write(f"- Tag: `{tag}`\n")
    fh.write(f"- Events: {len(events)}\n")
    fh.write(f"- Failed: {len(failed)}\n")
    fh.write(f"- Skipped: {len(skipped)}\n\n")
    fh.write("| Status | Name | Note |\n")
    fh.write("|---|---|---|\n")
    for event in events:
        fh.write(f"| {event['status']} | {event['name']} | {event.get('note', '')} |\n")
PY

printf '\nRelease evidence written to: %s\n' "${OUT_DIR}"
if [[ "${STRICT_RELEASE_EVIDENCE}" == "1" ]] && grep -q '"status": "failed"' "${events_file}"; then
    exit 1
fi
