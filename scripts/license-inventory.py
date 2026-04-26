#!/usr/bin/env python3
"""Generate a lightweight license/source inventory for tools, wheels, and datasets."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

KNOWN_LICENSES = {
    "aflplusplus": "Apache-2.0",
    "angr": "BSD-2-Clause",
    "boofuzz": "GPL-2.0-or-later",
    "codeql": "LicenseRef-GitHub-CodeQL",
    "ghidra": "Apache-2.0",
    "gitnexus": "UNKNOWN",
    "gitleaks": "MIT",
    "grype": "Apache-2.0",
    "honggfuzz": "Apache-2.0",
    "osv-scanner": "Apache-2.0",
    "semgrep": "LGPL-2.1-only",
    "syft": "Apache-2.0",
    "trufflehog": "AGPL-3.0-only",
    "yara": "BSD-3-Clause",
}


def dockerfile_args(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"ARG\s+([A-Z0-9_]+)=(.*)", line)
        if match:
            values[match.group(1)] = match.group(2)
    return values


def tool_entries() -> list[dict[str, str]]:
    entries = []
    for dockerfile in sorted((ROOT / "images").glob("*/Dockerfile")):
        image = dockerfile.parent.name
        args = dockerfile_args(dockerfile)
        for key, value in sorted(args.items()):
            if not any(token in key for token in ("VERSION", "REF", "COMMIT", "TAG")):
                continue
            component = key.lower()
            for suffix in ("_version", "_ref", "_commit", "_tag"):
                component = component.removesuffix(suffix)
            component = component.replace("_", "-")
            entries.append(
                {
                    "name": component,
                    "version": value,
                    "source": f"images/{image}/Dockerfile:{key}",
                    "spdx_license": KNOWN_LICENSES.get(component, "UNKNOWN"),
                    "classification": "runtime",
                    "image": f"spt-{image}",
                }
            )
    return entries


def wheel_entries(data_dir: Path) -> list[dict[str, str]]:
    entries = []
    req_dir = ROOT / "requirements" / "py311"
    if not req_dir.exists():
        return entries
    for req in sorted(req_dir.glob("*.in")):
        entries.append(
            {
                "name": f"python-wheel-group:{req.stem}",
                "version": "unlocked",
                "source": req.as_posix(),
                "spdx_license": "UNKNOWN",
                "classification": "build-time",
            }
        )

    wheels_manifest = data_dir / "python-wheels" / "py311" / "manifest.json"
    if wheels_manifest.exists():
        entries.append(
            {
                "name": "python-wheelhouse-py311",
                "version": "manifest",
                "source": wheels_manifest.as_posix(),
                "spdx_license": "SEE-MANIFEST",
                "classification": "data",
            }
        )
    return entries


def dataset_entries(data_dir: Path) -> list[dict[str, str]]:
    entries = []
    if not data_dir.exists():
        return entries
    for child in sorted(path for path in data_dir.iterdir() if path.is_dir()):
        metadata_path = child / "metadata.json"
        metadata = {}
        if metadata_path.exists():
            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        entries.append(
            {
                "name": child.name,
                "version": metadata.get("fetched_at", "unknown"),
                "source": metadata.get("source_url", metadata.get("source", child.name)),
                "spdx_license": metadata.get("license", "UNKNOWN"),
                "classification": "data",
            }
        )
    return entries


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", default="data-bundles/sources")
    parser.add_argument("--out-dir", default="artifacts/license-inventory")
    args = parser.parse_args()

    data_dir = ROOT / args.data_dir
    out_dir = ROOT / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    entries = tool_entries() + wheel_entries(data_dir) + dataset_entries(data_dir)
    manifest = {
        "schema_version": "1.0.0",
        "entries": entries,
        "summary": {
            "total": len(entries),
            "unknown_license": sum(1 for entry in entries if entry["spdx_license"] == "UNKNOWN"),
        },
    }

    json_path = out_dir / "license-inventory.json"
    md_path = out_dir / "license-inventory.md"
    json_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    with md_path.open("w", encoding="utf-8") as fh:
        fh.write("# License Inventory\n\n")
        fh.write(f"- Entries: {manifest['summary']['total']}\n")
        fh.write(f"- Unknown license entries: {manifest['summary']['unknown_license']}\n\n")
        fh.write("| Name | Version | License | Classification | Source |\n")
        fh.write("|---|---|---:|---:|---|\n")
        for entry in entries:
            fh.write(
                f"| `{entry['name']}` | {entry['version']} | {entry['spdx_license']} | "
                f"{entry['classification']} | {entry['source']} |\n"
            )

    print(f"License inventory JSON: {json_path}")
    print(f"License inventory report: {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
