#!/usr/bin/env python3
"""Report data bundle source freshness from per-dataset metadata.json files."""

from __future__ import annotations

import datetime as dt
import json
import sys
from pathlib import Path


CADENCE_DAYS = {
    "epss": 2,
    "nvd": 8,
    "cisa-kev": 8,
    "osv-db": 8,
    "github-advisory-db": 8,
    "cwe": 120,
    "capec": 120,
    "mitre-attack": 120,
    "semgrep-rules": 30,
    "codeql-packs": 30,
    "yara-rules": 30,
    "vendor-advisories": 30,
    "ladybug-extensions": 90,
    "python-wheels": 30,
}


def parse_timestamp(value: str | None) -> dt.datetime | None:
    if not value or value == "unknown":
        return None
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = dt.datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def status_for(age_days: float | None, expected_days: int) -> str:
    if age_days is None:
        return "unknown"
    if age_days <= expected_days:
        return "fresh"
    if age_days <= expected_days * 2:
        return "stale"
    return "expired"


def main() -> int:
    data_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "data-bundles/sources")
    out_dir = Path(sys.argv[2] if len(sys.argv) > 2 else "artifacts/data-freshness")
    out_dir.mkdir(parents=True, exist_ok=True)

    now = dt.datetime.now(dt.timezone.utc)
    rows = []
    if data_dir.exists():
        for child in sorted(data_dir.iterdir()):
            if not child.is_dir():
                continue
            metadata_path = child / "metadata.json"
            metadata = {}
            if metadata_path.exists():
                metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
            fetched_at = metadata.get("fetched_at")
            parsed = parse_timestamp(fetched_at)
            age_days = None if parsed is None else (now - parsed).total_seconds() / 86400
            expected_days = CADENCE_DAYS.get(child.name, 30)
            rows.append(
                {
                    "dataset": child.name,
                    "fetched_at": fetched_at or "unknown",
                    "age_days": None if age_days is None else round(age_days, 1),
                    "expected_days": expected_days,
                    "status": status_for(age_days, expected_days),
                    "source_url": metadata.get("source_url", "unknown"),
                }
            )

    json_path = out_dir / "data-freshness.json"
    md_path = out_dir / "data-freshness.md"
    json_path.write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")

    with md_path.open("w", encoding="utf-8") as fh:
        fh.write("# Data Bundle Freshness\n\n")
        fh.write(f"- Data directory: `{data_dir}`\n")
        fh.write(f"- Generated at: `{now.isoformat(timespec='seconds')}`\n\n")
        fh.write("| Dataset | Status | Age days | Expected cadence | Fetched at |\n")
        fh.write("|---|---:|---:|---:|---|\n")
        for row in rows:
            age = "" if row["age_days"] is None else row["age_days"]
            fh.write(
                f"| `{row['dataset']}` | {row['status']} | {age} | "
                f"{row['expected_days']} | {row['fetched_at']} |\n"
            )

    print(f"Data freshness JSON: {json_path}")
    print(f"Data freshness report: {md_path}")
    for row in rows:
        age = "unknown" if row["age_days"] is None else f"{row['age_days']}d"
        print(f"{row['status']:7} {row['dataset']:24} age={age} cadence={row['expected_days']}d")

    return 1 if any(row["status"] == "expired" for row in rows) else 0


if __name__ == "__main__":
    raise SystemExit(main())
