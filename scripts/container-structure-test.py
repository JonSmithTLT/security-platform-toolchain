#!/usr/bin/env python3
"""Lightweight container structure checks for built SPT images."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


REQUIRED_LABELS = [
    "org.opencontainers.image.source",
    "org.opencontainers.image.revision",
    "org.opencontainers.image.version",
    "org.opencontainers.image.created",
    "org.opencontainers.image.licenses",
    "org.security-platform-toolchain.schema-version",
]

ROOT_ALLOWED = {"spt-python-wheelhouse-py311"}


def inspect_image(image_ref: str) -> dict | None:
    proc = subprocess.run(
        ["docker", "image", "inspect", image_ref],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        return None
    return json.loads(proc.stdout)[0]


def check_image(image_name: str, image_ref: str) -> dict:
    data = inspect_image(image_ref)
    failures = []
    warnings = []
    if data is None:
        return {"image": image_ref, "status": "failed", "failures": [f"image not found or not inspectable: {image_ref}"], "warnings": []}

    config = data.get("Config", {}) or {}
    labels = config.get("Labels", {}) or {}
    missing_labels = [label for label in REQUIRED_LABELS if not labels.get(label)]
    if missing_labels:
        failures.append(f"missing required labels: {', '.join(missing_labels)}")

    if not config.get("Cmd") and not config.get("Entrypoint"):
        failures.append("missing Cmd or Entrypoint")

    user = config.get("User") or ""
    if image_name not in ROOT_ALLOWED and user in {"", "0", "root"}:
        failures.append("image runs as root or does not declare a non-root user")

    env = config.get("Env") or []
    if image_name != "spt-python-wheelhouse-py311" and not any(item.startswith("ARTIFACTS_DIR=") for item in env):
        warnings.append("ARTIFACTS_DIR is not declared in image env")

    return {
        "image": image_ref,
        "status": "failed" if failures else "passed",
        "failures": failures,
        "warnings": warnings,
        "user": user,
        "cmd": config.get("Cmd"),
        "entrypoint": config.get("Entrypoint"),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--images", required=True)
    parser.add_argument("--out-dir", default="artifacts/container-structure")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    image_names = [f"spt-{name}" for name in args.images.split()]
    results = [
        check_image(image_name, f"{args.registry}/{image_name}:{args.tag}")
        for image_name in image_names
    ]
    failed = [result for result in results if result["status"] == "failed"]

    json_path = out_dir / "container-structure-results.json"
    md_path = out_dir / "container-structure-results.md"
    json_path.write_text(json.dumps({"schema_version": "1.0.0", "results": results}, indent=2) + "\n", encoding="utf-8")

    with md_path.open("w", encoding="utf-8") as fh:
        fh.write("# Container Structure Test Results\n\n")
        fh.write(f"- Images: {len(results)}\n")
        fh.write(f"- Failed: {len(failed)}\n\n")
        fh.write("| Image | Status | User | Failures | Warnings |\n")
        fh.write("|---|---:|---:|---|---|\n")
        for result in results:
            fh.write(
                f"| `{result['image']}` | {result['status']} | `{result.get('user', '')}` | "
                f"{'; '.join(result['failures'])} | {'; '.join(result['warnings'])} |\n"
            )

    print(f"Container structure JSON: {json_path}")
    print(f"Container structure report: {md_path}")
    print(f"Container structure failures: {len(failed)}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
