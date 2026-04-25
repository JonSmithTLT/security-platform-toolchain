#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TAG="${TAG:-latest}"
DATA_DIR="${DATA_DIR:-data-bundles/sources}"
DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR:-data-bundles/out}"
SPLIT_SIZE="${SPLIT_SIZE:-1900M}"
SANITIZED="${SANITIZED:-false}"
SKIP_FETCH="${SKIP_FETCH:-0}"
TAR="${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.tar"
MANIFEST="${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.manifest.json"
SOURCE_SUMS="${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.source-checksums.sha256"

if [[ "${SKIP_FETCH}" != "1" ]]; then
    make data-fetch TAG="${TAG}"
fi

mkdir -p "${DATA_BUNDLE_DIR}"

if find "${DATA_DIR}" -type f ! -name SHA256SUMS ! -name metadata.json | grep -q .; then
    (
        cd "${DATA_DIR}"
        find . -type f ! -name SHA256SUMS ! -name metadata.json -print0 \
            | sort -z \
            | xargs -0 sha256sum > "${ROOT_DIR}/${SOURCE_SUMS}"
    )
else
    : > "${SOURCE_SUMS}"
fi

python3 - "${DATA_DIR}" "${MANIFEST}" "${SANITIZED}" <<'PY'
import datetime as dt
import hashlib
import json
import os
import sys

data_dir, manifest_path, sanitized = sys.argv[1], sys.argv[2], sys.argv[3].lower() == "true"
datasets = []
for name in sorted(os.listdir(data_dir)):
    path = os.path.join(data_dir, name)
    if not os.path.isdir(path):
        continue
    metadata_path = os.path.join(path, "metadata.json")
    metadata = {}
    if os.path.exists(metadata_path):
        with open(metadata_path, "r", encoding="utf-8") as fh:
            metadata = json.load(fh)
    digest = hashlib.sha256()
    file_count = 0
    for root, _, files in os.walk(path):
        for filename in sorted(files):
            full = os.path.join(root, filename)
            rel = os.path.relpath(full, path).replace(os.sep, "/")
            digest.update(rel.encode("utf-8"))
            with open(full, "rb") as fh:
                for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                    digest.update(chunk)
            file_count += 1
    datasets.append({
        "name": name,
        "source": metadata.get("source", name),
        "source_url": metadata.get("source_url", "unknown"),
        "fetched_at": metadata.get("fetched_at", "unknown"),
        "file_count": file_count,
        "sha256": digest.hexdigest(),
        "purpose": "offline security research and vulnerability intelligence",
        "risk_flags": {
            "contains_live_malware_samples": False,
            "contains_real_credentials": False,
            "contains_advisory_poc_text": name in {"github-advisory-db", "nvd", "osv", "vendor-advisories"},
            "contains_exploit_commands": name in {"github-advisory-db", "nvd", "yara-rules", "vendor-advisories"},
            "sanitized": sanitized,
        },
    })

manifest = {
    "schema_version": "1.0.0",
    "generated_at": dt.datetime.now(dt.UTC).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "sanitized": sanitized,
    "risk_flags": {
        "contains_live_malware_samples": False,
        "contains_real_credentials": False,
        "contains_advisory_poc_text": not sanitized,
        "contains_exploit_commands": not sanitized,
        "sanitized": sanitized,
    },
    "datasets": datasets,
}
with open(manifest_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
PY

make data-bundle TAG="${TAG}" DATA_DIR="${DATA_DIR}" DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR}"

rm -f "${TAR}.part-"*
split -b "${SPLIT_SIZE}" "${TAR}" "${TAR}.part-"
sha256sum "${TAR}".part-* > "${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.parts.sha256"

printf 'Data bundle: %s\n' "${TAR}"
printf 'Data manifest: %s\n' "${MANIFEST}"
printf 'Data source checksums: %s\n' "${SOURCE_SUMS}"

