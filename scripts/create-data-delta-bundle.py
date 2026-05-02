#!/usr/bin/env python3
"""Create a dataset-level delta bundle from a previous source checksum file."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import tarfile
from pathlib import Path


def iter_files(root: Path):
    for path in sorted(root.rglob("*")):
        if path.is_file():
            rel = path.relative_to(root).as_posix()
            if rel.endswith(".sha256") or rel.endswith("SHA256SUMS"):
                continue
            yield path, rel


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_sums(path: Path) -> dict[str, str]:
    sums: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        digest, rel = line.split(None, 1)
        sums[rel.removeprefix("./")] = digest
    return sums


def load_metadata(path: Path) -> dict:
    metadata_path = path / "metadata.json"
    if metadata_path.exists():
        return json.loads(metadata_path.read_text(encoding="utf-8"))
    return {}


def stable_json_digest(data) -> str:
    digest = hashlib.sha256()
    digest.update(json.dumps(data, sort_keys=True, separators=(",", ":")).encode("utf-8"))
    return digest.hexdigest()


def dataset_digest(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(stable_json_digest(load_metadata(path)).encode("utf-8"))

    source_digest_files = []
    for child in sorted(path.iterdir(), key=lambda p: p.name):
        if child.is_file() and (child.name == "SHA256SUMS" or child.name.endswith(".sha256")):
            source_digest_files.append(child)

    for child in source_digest_files:
        digest.update(child.name.encode("utf-8"))
        with child.open("rb") as fh:
            for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", default="data-bundles/sources")
    parser.add_argument("--base-source-checksums", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--manifest-out", required=True)
    parser.add_argument("--tag", default="latest")
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    out = Path(args.out)
    manifest_out = Path(args.manifest_out)
    out.parent.mkdir(parents=True, exist_ok=True)
    manifest_out.parent.mkdir(parents=True, exist_ok=True)

    base = load_sums(Path(args.base_source_checksums))
    base_has_dataset_entries = any("/" not in rel for rel in base)
    base_has_file_entries = any("/" in rel for rel in base)
    if base_has_dataset_entries and base_has_file_entries:
        raise SystemExit(
            "base source checksums mix dataset-level and file-level entries; "
            "regenerate the base checksum file with one DATA_MANIFEST_CHECKSUM_MODE"
        )

    included: list[str]
    mode: str
    if base_has_dataset_entries:
        mode = "dataset"
        dataset_dirs = {
            child.name: child
            for child in sorted(data_dir.iterdir(), key=lambda p: p.name)
            if child.is_dir()
        }
        current = {name: dataset_digest(path) for name, path in dataset_dirs.items()}
        added = sorted(name for name in current if name not in base)
        modified = sorted(name for name in current if name in base and current[name] != base[name])
        removed = sorted(name for name in base if name not in current)
        changed_datasets = set(added + modified)
        included = [
            rel
            for _, rel in iter_files(data_dir)
            if rel.split("/", 1)[0] in changed_datasets
        ]
    else:
        mode = "file"
        current = {rel: sha256(path) for path, rel in iter_files(data_dir)}
        added = sorted(rel for rel in current if rel not in base)
        modified = sorted(rel for rel in current if rel in base and current[rel] != base[rel])
        removed = sorted(rel for rel in base if rel not in current)
        included = added + modified

    manifest = {
        "schema_version": "1.0.0",
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "tag": args.tag,
        "base_source_checksums": str(args.base_source_checksums),
        "checksum_mode": mode,
        "data_dir": str(data_dir),
        "summary": {
            "added": len(added),
            "modified": len(modified),
            "removed": len(removed),
            "included_files": len(included),
        },
        "added": added,
        "modified": modified,
        "removed": removed,
    }
    manifest_out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    tar_mode = "w:gz" if out.name.endswith(".gz") else "w"
    with tarfile.open(out, tar_mode) as tar:
        tar.add(manifest_out, arcname="delta-manifest.json")
        for rel in included:
            tar.add(data_dir / rel, arcname=f"sources/{rel}")

    print(f"Data delta bundle: {out}")
    print(f"Data delta manifest: {manifest_out}")
    print(f"Included files: {len(included)}")
    print(f"Removed files: {len(removed)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
