#!/usr/bin/env bash
set -euo pipefail

TAG="${TAG:-latest}"
DATA_DIR="${DATA_DIR:-data-bundles/sources}"
DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR:-data-bundles/out}"
SANITIZED="${SANITIZED:-false}"
MANIFEST="${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.manifest.json"
SOURCE_SUMS="${DATA_BUNDLE_DIR}/spt-data-bundle-${TAG}.source-checksums.sha256"

mkdir -p "${DATA_BUNDLE_DIR}"

python3 - "${DATA_DIR}" "${MANIFEST}" "${SOURCE_SUMS}" "${SANITIZED}" <<'PY'
import datetime as dt
import hashlib
import json
import os
import sys
import time

data_dir, manifest_path, source_sums_path, sanitized_arg = sys.argv[1:5]
sanitized = sanitized_arg.lower() == "true"
progress_every_files = int(os.environ.get("DATA_MANIFEST_PROGRESS_FILES", "5000"))
progress_every_seconds = int(os.environ.get("DATA_MANIFEST_PROGRESS_SECONDS", "15"))
reuse_source_sums = os.environ.get("DATA_MANIFEST_REUSE_SOURCE_SUMS", "0") == "1"
datasets = []

def log(message):
    print(f"==> {message}", file=sys.stderr, flush=True)

def iter_files(path):
    for root, dirs, files in os.walk(path):
        dirs.sort()
        for filename in sorted(files):
            yield os.path.join(root, filename)

start_time = time.monotonic()

def load_metadata(path, name):
    metadata_path = os.path.join(path, "metadata.json")
    if os.path.exists(metadata_path):
        with open(metadata_path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    return {}

def append_dataset(name, metadata, file_count, digest, checksum_mode):
    datasets.append({
        "name": name,
        "source": metadata.get("source", name),
        "source_url": metadata.get("source_url", "unknown"),
        "fetched_at": metadata.get("fetched_at", "unknown"),
        "file_count": file_count,
        "sha256": digest,
        "checksum_mode": checksum_mode,
        "purpose": "offline security research and vulnerability intelligence",
        "risk_flags": {
            "contains_live_malware_samples": False,
            "contains_real_credentials": False,
            "contains_advisory_poc_text": name in {"github-advisory-db", "nvd", "osv", "vendor-advisories"},
            "contains_exploit_commands": name in {"github-advisory-db", "nvd", "yara-rules", "vendor-advisories"},
            "sanitized": sanitized,
        },
    })

if reuse_source_sums and os.path.exists(source_sums_path) and os.path.getsize(source_sums_path) > 0:
    log(f"Reusing existing data source checksums from {source_sums_path}")
    grouped = {}
    with open(source_sums_path, "r", encoding="utf-8") as sums_fh:
        for line in sums_fh:
            line = line.rstrip("\n")
            if not line:
                continue
            digest, rel = line.split(None, 1)
            rel = rel.removeprefix("./")
            parts = rel.split("/", 1)
            if len(parts) != 2:
                continue
            grouped.setdefault(parts[0], []).append((parts[1], digest))

    for name in sorted(os.listdir(data_dir)):
        path = os.path.join(data_dir, name)
        if not os.path.isdir(path):
            continue
        metadata = load_metadata(path, name)
        digest = hashlib.sha256()
        entries = grouped.get(name, [])
        for rel_dataset, file_digest in entries:
            digest.update(rel_dataset.encode("utf-8"))
            digest.update(file_digest.encode("utf-8"))
        append_dataset(name, metadata, len(entries), digest.hexdigest(), "source-checksums-reused")
        log(f"Reused {name}: {len(entries)} checksummed files")
else:
    log(f"Writing data source checksums to {source_sums_path}")
    with open(source_sums_path, "w", encoding="utf-8") as sums_fh:
        for name in sorted(os.listdir(data_dir)):
            path = os.path.join(data_dir, name)
            if not os.path.isdir(path):
                continue

            dataset_start = time.monotonic()
            next_progress = dataset_start + progress_every_seconds
            log(f"Hashing dataset: {name}")

            metadata = load_metadata(path, name)

            digest = hashlib.sha256()
            file_count = 0
            byte_count = 0
            for full in iter_files(path):
                filename = os.path.basename(full)
                rel_dataset = os.path.relpath(full, path).replace(os.sep, "/")
                rel_source = os.path.join(name, rel_dataset).replace(os.sep, "/")
                file_digest = hashlib.sha256()
                digest.update(rel_dataset.encode("utf-8"))
                with open(full, "rb") as fh:
                    for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                        digest.update(chunk)
                        file_digest.update(chunk)
                        byte_count += len(chunk)
                file_count += 1
                if filename not in {"SHA256SUMS", "metadata.json"}:
                    sums_fh.write(f"{file_digest.hexdigest()}  ./{rel_source}\n")
                now = time.monotonic()
                if (
                    progress_every_files > 0 and file_count % progress_every_files == 0
                ) or now >= next_progress:
                    mib = byte_count / (1024 * 1024)
                    elapsed = max(now - dataset_start, 0.001)
                    rate = file_count / elapsed
                    log(f"  {name}: {file_count} files, {mib:.1f} MiB hashed, {rate:.1f} files/s")
                    next_progress = now + progress_every_seconds

            sums_fh.flush()
            dataset_elapsed = time.monotonic() - dataset_start
            log(f"Finished {name}: {file_count} files in {dataset_elapsed:.1f}s")
            append_dataset(name, metadata, file_count, digest.hexdigest(), "content")

log(f"Writing data bundle manifest to {manifest_path}")
manifest = {
    "schema_version": "1.0.0",
    "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
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
log(f"Data manifest complete in {time.monotonic() - start_time:.1f}s")
PY

printf 'Data manifest: %s\n' "${MANIFEST}"
printf 'Data source checksums: %s\n' "${SOURCE_SUMS}"
