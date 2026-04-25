#!/usr/bin/env python3
"""Emit an SPT artifact manifest for files under ARTIFACTS_DIR."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import mimetypes
import os
from pathlib import Path


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def role_for(relative: str) -> str:
    name = Path(relative).name
    if relative == "job-report.json":
        return "job-report"
    if relative == "manifest.json":
        return "manifest"
    if name == "tool-result.json":
        return "tool-result"
    if relative.startswith("logs/"):
        return "log"
    if relative.startswith("sbom/"):
        return "sbom"
    if "/raw/" in relative:
        return "raw-output"
    if "/evidence/" in relative:
        return "evidence"
    return "other"


def tool_for(relative: str) -> str | None:
    parts = Path(relative).parts
    if len(parts) >= 2 and parts[0] == "results":
        return parts[1]
    if len(parts) >= 2 and parts[0] == "logs":
        return Path(parts[1]).stem
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifacts-dir", default=os.environ.get("ARTIFACTS_DIR", "/artifacts"))
    parser.add_argument("--output", default=None)
    parser.add_argument("--job-id", default=os.environ.get("JOB_ID", "unknown"))
    args = parser.parse_args()

    artifacts_dir = Path(args.artifacts_dir)
    output = Path(args.output) if args.output else artifacts_dir / "manifest.json"
    entries = []

    for path in sorted(artifacts_dir.rglob("*")):
        if not path.is_file() or path == output:
            continue
        relative = path.relative_to(artifacts_dir).as_posix()
        mime_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        entry = {
            "path": relative,
            "sha256": sha256(path),
            "size_bytes": path.stat().st_size,
            "mime_type": mime_type,
            "role": role_for(relative),
        }
        tool = tool_for(relative)
        if tool:
            entry["tool"] = tool
        entries.append(entry)

    manifest = {
        "schema_version": "1.0.0",
        "job_id": args.job_id,
        "generated_at": utc_now(),
        "artifacts": entries,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"[INFO] Artifact manifest written to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
