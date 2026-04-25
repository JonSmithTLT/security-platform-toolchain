#!/usr/bin/env python3
"""Chunk offline intelligence files into portable JSONL records."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path


SUPPORTED_SUFFIXES = {".txt", ".md", ".json", ".jsonl", ".csv", ".yml", ".yaml"}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def iter_files(root: Path) -> list[Path]:
    if root.is_file():
        return [root]
    return sorted(path for path in root.rglob("*") if path.is_file() and path.suffix.lower() in SUPPORTED_SUFFIXES)


def chunks(text: str, size: int = 2400) -> list[str]:
    clean = "\n".join(line.rstrip() for line in text.splitlines()).strip()
    if not clean:
        return []
    return [clean[index:index + size] for index in range(0, len(clean), size)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--chunks-out", required=True)
    parser.add_argument("--manifest-out", required=True)
    args = parser.parse_args()

    source = Path(args.input)
    chunks_out = Path(args.chunks_out)
    manifest_out = Path(args.manifest_out)
    chunks_out.parent.mkdir(parents=True, exist_ok=True)
    manifest_out.parent.mkdir(parents=True, exist_ok=True)

    records = []
    files = iter_files(source)
    imported_at = utc_now()
    with chunks_out.open("w", encoding="utf-8") as out:
        for path in files:
            text = path.read_text(encoding="utf-8", errors="replace")
            for ordinal, chunk in enumerate(chunks(text), start=1):
                record = {
                    "id": sha256_text(f"{args.dataset}|{args.version}|{path}|{ordinal}|{chunk}")[:24],
                    "dataset": args.dataset,
                    "dataset_version": args.version,
                    "imported_at": imported_at,
                    "source_path": str(path),
                    "chunk_index": ordinal,
                    "text": chunk,
                    "sha256": sha256_text(chunk),
                }
                out.write(json.dumps(record, sort_keys=True) + "\n")
                records.append(record)

    manifest = {
        "schema_version": "1.0.0",
        "dataset": args.dataset,
        "dataset_version": args.version,
        "imported_at": imported_at,
        "input": str(source),
        "file_count": len(files),
        "chunk_count": len(records),
    }
    manifest_out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
