#!/usr/bin/env python3
"""Compare local FUTURE_WORK Tier 1 checkboxes with repo evidence."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FUTURE_WORK = ROOT / "FUTURE_WORK.md"
MAKEFILE = ROOT / "Makefile"


EVIDENCE = {
    "Release preflight doctor": ["scripts/doctor.sh", "make:doctor"],
    "Release stage ledger": ["scripts/release-smoke-build.sh:RELEASE_LEDGER"],
    "Build timing report": ["scripts/build-with-metrics.sh", "make:build-report"],
    "Backlog/release-state reconciliation": ["scripts/backlog-status.py", "make:backlog-status"],
    "Host path safety guard": ["scripts/doctor.sh:ALLOW_SLOW_WORKTREE"],
    "Python 3.11 wheelhouse": ["images/python-wheelhouse-py311/Dockerfile", "make:python-wheelhouse-image"],
    "`make help`": ["make:help"],
    "Explicit cleanup targets": ["make:clean-bundles", "make:clean-artifacts", "make:clean-data-sources", "make:clean-all-generated"],
    "Image size tracking": ["make:image-sizes"],
    "Move release builds off `/mnt/c`": ["scripts/prepare-native-worktree.sh", "make:native-worktree"],
    "Resumable release workflow": ["scripts/release-smoke-build.sh:RESUME_FROM"],
    "GitHub Advisory DB optional fetch": ["make:data-fetch-full", "data-bundles/fetch/fetch-all.sh:INCLUDE_GITHUB_ADVISORY_DB:-0"],
    "Data manifest checksum modes": ["scripts/write-data-bundle-manifest.sh:DATA_MANIFEST_CHECKSUM_MODE"],
    "Tool version inventory / drift report": ["scripts/tool-version-inventory.sh", "make:tool-versions-installed", "make:tool-drift-check"],
    "Parallel builds": ["scripts/release-smoke-build.sh:BUILD_JOBS"],
    "BuildKit cache mounts": ["images/ghidra-mcp/Dockerfile:--mount=type=cache"],
    "Data bundle freshness dashboard": ["scripts/data-check-freshness.py", "make:data-check-freshness"],
    "Incremental NVD fetch": ["data-bundles/fetch/fetch-nvd.sh:NVD_INCREMENTAL"],
}


def make_targets() -> set[str]:
    text = MAKEFILE.read_text(encoding="utf-8")
    targets = set()
    for line in text.splitlines():
        match = re.match(r"^([A-Za-z0-9_.-]+):", line)
        if match:
            targets.add(match.group(1))
    return targets


def evidence_present(spec: str, targets: set[str]) -> bool:
    if spec.startswith("make:"):
        return spec.split(":", 1)[1] in targets
    if ":" in spec:
        path_text, needle = spec.split(":", 1)
        path = ROOT / path_text
        return path.exists() and needle in path.read_text(encoding="utf-8", errors="replace")
    return (ROOT / spec).exists()


def parse_tier1() -> list[dict[str, object]]:
    text = FUTURE_WORK.read_text(encoding="utf-8", errors="replace")
    tier_match = re.search(r"### Tier 1.*?\n(?P<body>.*?)(?:\n### Tier 2|\Z)", text, re.S)
    if not tier_match:
        raise SystemExit("Tier 1 section not found in FUTURE_WORK.md")

    items = []
    for line in tier_match.group("body").splitlines():
        match = re.match(r"- \[(?P<mark>[ xX])\] \*\*(?P<title>.*?)\*\*", line)
        if match:
            items.append({"title": match.group("title"), "checked": match.group("mark").lower() == "x"})
    return items


def main() -> int:
    targets = make_targets()
    items = parse_tier1()
    rows = []
    mismatches = 0

    for item in items:
        title = str(item["title"])
        evidence_specs = EVIDENCE.get(title, [])
        present = all(evidence_present(spec, targets) for spec in evidence_specs) if evidence_specs else None
        checked = bool(item["checked"])
        if present is not None and checked != present:
            mismatches += 1
        rows.append({**item, "evidence": present, "evidence_specs": evidence_specs})

    out_dir = ROOT / "artifacts" / "backlog-status"
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "tier1-backlog-status.json"
    md_path = out_dir / "tier1-backlog-status.md"
    json_path.write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")

    with md_path.open("w", encoding="utf-8") as fh:
        fh.write("# Tier 1 Backlog Status\n\n")
        fh.write("| Item | Checked | Evidence | Evidence specs |\n")
        fh.write("|---|---:|---:|---|\n")
        for row in rows:
            evidence = "n/a" if row["evidence"] is None else str(row["evidence"]).lower()
            specs = ", ".join(f"`{spec}`" for spec in row["evidence_specs"])
            fh.write(f"| {row['title']} | {str(row['checked']).lower()} | {evidence} | {specs} |\n")

    print(f"Backlog status JSON: {json_path}")
    print(f"Backlog status report: {md_path}")
    print(f"Backlog/evidence mismatches: {mismatches}")
    return 1 if mismatches else 0


if __name__ == "__main__":
    raise SystemExit(main())
