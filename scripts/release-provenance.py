#!/usr/bin/env python3
"""Generate SPT image provenance predicates for release attestation."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    if not path.exists():
        return ""
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def docker_inspect(image_ref: str) -> dict[str, Any]:
    proc = subprocess.run(
        ["docker", "image", "inspect", image_ref],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if proc.returncode != 0:
        return {}
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {}
    return data[0] if data else {}


def predicate_for(args: argparse.Namespace, image: str) -> dict[str, Any]:
    image_ref = f"{args.registry}/spt-{image}:{args.tag}"
    inspected = docker_inspect(image_ref)
    labels = inspected.get("Config", {}).get("Labels", {}) if inspected else {}
    repo_digests = inspected.get("RepoDigests", []) if inspected else []
    subject_digest = repo_digests[0] if repo_digests else image_ref

    return {
        "_type": "https://in-toto.io/Statement/v1",
        "subject": [
            {
                "name": image_ref,
                "digest": {"image": subject_digest},
            }
        ],
        "predicateType": "https://slsa.dev/provenance/v1",
        "predicate": {
            "buildDefinition": {
                "buildType": "https://github.com/JonSmithTLT/security-platform-toolchain/spt-release",
                "externalParameters": {
                    "registry": args.registry,
                    "tag": args.tag,
                    "image": image,
                    "source_date_epoch": args.source_date_epoch,
                    "git_revision": args.git_revision,
                },
                "resolvedDependencies": [
                    {
                        "uri": str(Path(args.image_manifest)),
                        "digest": {"sha256": sha256_file(Path(args.image_manifest)).removeprefix("sha256:")},
                    },
                    {
                        "uri": str(Path(args.data_manifest)),
                        "digest": {"sha256": sha256_file(Path(args.data_manifest)).removeprefix("sha256:")},
                    },
                ],
            },
            "runDetails": {
                "builder": {"id": "security-platform-toolchain"},
                "metadata": {
                    "invocationId": f"spt-release-{args.tag}",
                    "startedOn": labels.get("org.opencontainers.image.created", ""),
                    "finishedOn": utc_now(),
                },
            },
            "spt": {
                "schema_version": "1.0.0",
                "image_id": inspected.get("Id", ""),
                "repo_digests": repo_digests,
                "labels": labels,
                "release_ledger": args.release_ledger,
            },
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--images", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--git-revision", default="unknown")
    parser.add_argument("--source-date-epoch", default="")
    parser.add_argument("--image-manifest", default="")
    parser.add_argument("--data-manifest", default="")
    parser.add_argument("--release-ledger", default="")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for image in args.images.split():
        predicate = predicate_for(args, image)
        path = out_dir / f"spt-{image}.provenance.json"
        path.write_text(json.dumps(predicate, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"Provenance predicate: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
