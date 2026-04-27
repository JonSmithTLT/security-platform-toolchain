#!/usr/bin/env python3
"""Generate a compact markdown release evidence summary."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8", errors="replace"))


def read_lines(path: Path) -> list[str]:
    if not path.exists():
        return []
    return [line.strip() for line in path.read_text(encoding="utf-8", errors="replace").splitlines() if line.strip()]


def checksum_line(path: Path) -> str:
    lines = read_lines(path)
    return lines[0] if lines else ""


def ledger_counts(path: Path) -> dict[str, int]:
    counts: dict[str, int] = {}
    for line in read_lines(path):
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        status = str(record.get("status") or "unknown")
        counts[status] = counts.get(status, 0) + 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--bundle-dir", default="offline-bundles/out")
    parser.add_argument("--data-bundle-dir", default="data-bundles/out")
    parser.add_argument("--release-ledger", required=True)
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    tag = args.tag
    bundle_dir = Path(args.bundle_dir)
    data_dir = Path(args.data_bundle_dir)
    evidence_dir = Path(args.evidence_dir)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    evidence_summary = read_json(evidence_dir / "release-evidence-summary.json")
    counts = ledger_counts(Path(args.release_ledger))
    upload_assets = read_lines(bundle_dir / f"spt-release-{tag}.upload-assets.txt")

    image_sum = checksum_line(bundle_dir / f"spt-bundle-{tag}.tar.gz.sha256")
    data_sum = checksum_line(data_dir / f"spt-data-bundle-{tag}.tar.gz.sha256")

    with out.open("w", encoding="utf-8") as fh:
        fh.write(f"# SPT Release Summary {tag}\n\n")
        fh.write("## Bundle Checksums\n\n")
        fh.write(f"- Image bundle: `{image_sum or 'missing'}`\n")
        fh.write(f"- Data bundle: `{data_sum or 'missing'}`\n\n")
        fh.write("## Release Stages\n\n")
        if counts:
            for status, count in sorted(counts.items()):
                fh.write(f"- {status}: {count}\n")
        else:
            fh.write("- release ledger unavailable\n")
        fh.write("\n## Evidence\n\n")
        if evidence_summary:
            fh.write(f"- Events: {evidence_summary.get('event_count', 0)}\n")
            fh.write(f"- Failed: {evidence_summary.get('failed_count', 0)}\n")
            fh.write(f"- Skipped: {evidence_summary.get('skipped_count', 0)}\n")
        else:
            fh.write("- release evidence summary unavailable\n")
        fh.write("\n## Upload Assets\n\n")
        if upload_assets:
            for asset in upload_assets:
                fh.write(f"- `{asset}`\n")
        else:
            fh.write("- upload asset manifest unavailable\n")

    print(f"Release summary: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
