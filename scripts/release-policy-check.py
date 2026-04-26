#!/usr/bin/env python3
"""Apply lightweight release policy gates to collected evidence."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


def docker_image_size(image_ref: str) -> int | None:
    proc = subprocess.run(
        ["docker", "image", "inspect", image_ref, "--format", "{{.Size}}"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if proc.returncode != 0:
        return None
    try:
        return int(proc.stdout.strip())
    except ValueError:
        return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--registry", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--images", required=True)
    parser.add_argument("--max-image-mib", type=int, default=4096)
    parser.add_argument("--allow-failed-evidence", action="store_true")
    args = parser.parse_args()

    evidence_dir = Path(args.evidence_dir)
    images = args.images.split()
    failures: list[str] = []
    warnings: list[str] = []

    required = [
        evidence_dir / "manifest.json",
        evidence_dir / "release-evidence-summary.json",
        evidence_dir / "release-evidence-summary.md",
        evidence_dir / "reports" / "image-sizes.md",
        evidence_dir / "tool-inventory" / "installed-tool-versions.json",
        evidence_dir / "tool-inventory" / "tool-version-drift.md",
    ]
    for path in required:
        if not path.exists():
            failures.append(f"missing required evidence file: {path}")

    events_path = evidence_dir / "release-evidence-events.jsonl"
    if events_path.exists():
        failed_events = []
        for line in events_path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            event = json.loads(line)
            if event.get("status") == "failed":
                failed_events.append(event["name"])
        if failed_events and not args.allow_failed_evidence:
            failures.append(f"failed evidence events: {', '.join(failed_events)}")
        elif failed_events:
            warnings.append(f"failed evidence events allowed: {', '.join(failed_events)}")
    else:
        failures.append(f"missing evidence event log: {events_path}")

    max_bytes = args.max_image_mib * 1024 * 1024
    for image in images:
        image_ref = f"{args.registry}/spt-{image}:{args.tag}"
        size = docker_image_size(image_ref)
        if size is None:
            failures.append(f"image not inspectable: {image_ref}")
            continue
        if size > max_bytes:
            failures.append(f"image exceeds max size: {image_ref} size={size} max={max_bytes}")

    out = {
        "schema_version": "1.0.0",
        "status": "failed" if failures else "passed",
        "failures": failures,
        "warnings": warnings,
        "max_image_mib": args.max_image_mib,
    }
    out_path = evidence_dir / "release-policy-result.json"
    md_path = evidence_dir / "release-policy-result.md"
    out_path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")

    with md_path.open("w", encoding="utf-8") as fh:
        fh.write("# Release Policy Result\n\n")
        fh.write(f"- Status: **{out['status']}**\n")
        fh.write(f"- Max image size: {args.max_image_mib} MiB\n\n")
        if failures:
            fh.write("## Failures\n\n")
            for failure in failures:
                fh.write(f"- {failure}\n")
            fh.write("\n")
        if warnings:
            fh.write("## Warnings\n\n")
            for warning in warnings:
                fh.write(f"- {warning}\n")

    print(f"Release policy JSON: {out_path}")
    print(f"Release policy report: {md_path}")
    print(f"Release policy status: {out['status']}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
