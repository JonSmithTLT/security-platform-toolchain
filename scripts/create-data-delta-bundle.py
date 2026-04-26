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

    with tarfile.open(out, "w") as tar:
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
