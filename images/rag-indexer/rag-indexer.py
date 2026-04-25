#!/usr/bin/env python3
"""Build a small offline SQLite FTS index from JSONL chunks."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
from pathlib import Path


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--sqlite-out", required=True)
    parser.add_argument("--manifest-out", required=True)
    args = parser.parse_args()

    input_path = Path(args.input)
    sqlite_out = Path(args.sqlite_out)
    manifest_out = Path(args.manifest_out)
    sqlite_out.parent.mkdir(parents=True, exist_ok=True)
    manifest_out.parent.mkdir(parents=True, exist_ok=True)
    if sqlite_out.exists():
        sqlite_out.unlink()

    conn = sqlite3.connect(sqlite_out)
    conn.execute("create virtual table docs using fts5(id, dataset, source_path, text)")
    count = 0
    if input_path.exists():
        for line in input_path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            record = json.loads(line)
            conn.execute(
                "insert into docs(id, dataset, source_path, text) values (?, ?, ?, ?)",
                (record.get("id"), record.get("dataset"), record.get("source_path"), record.get("text")),
            )
            count += 1
    conn.commit()
    conn.close()

    manifest = {
        "schema_version": "1.0.0",
        "generated_at": utc_now(),
        "input": str(input_path),
        "index": str(sqlite_out),
        "document_count": count,
    }
    manifest_out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
