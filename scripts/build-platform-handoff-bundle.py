#!/usr/bin/env python3
"""Build a versioned platform handoff contract and bundle tarball."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import shutil
import subprocess
import tarfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_VERSION = "1.0.0"


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def copy_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def add_optional_file(src: Path, dst: Path, missing: list[str]) -> bool:
    if not src.exists():
        missing.append(str(src))
        return False
    copy_file(src, dst)
    return True


def add_release_evidence(release_evidence_dir: Path, out_dir: Path) -> list[str]:
    target = out_dir / "release-evidence"
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(release_evidence_dir, target)
    return [p.relative_to(out_dir).as_posix() for p in sorted(target.rglob("*")) if p.is_file()]


def add_normalized_results(results_dir: Path, out_dir: Path) -> tuple[list[str], list[str]]:
    findings: list[str] = []
    candidate_correlations: list[str] = []

    if not results_dir.exists():
        return findings, candidate_correlations

    for tool_result in sorted(results_dir.glob("*/tool-result.json")):
        tool = tool_result.parent.name
        dst = out_dir / "findings" / "tool-results" / tool / "tool-result.json"
        copy_file(tool_result, dst)
        findings.append(dst.relative_to(out_dir).as_posix())

    for candidate in sorted(results_dir.glob("*/normalized/candidate-correlations.json")):
        tool = candidate.parents[1].name
        dst = out_dir / "findings" / "candidate-correlations" / tool / "candidate-correlations.json"
        copy_file(candidate, dst)
        candidate_correlations.append(dst.relative_to(out_dir).as_posix())

    return findings, candidate_correlations


def add_bundle_manifests(
    tag: str,
    offline_bundle_dir: Path,
    data_bundle_dir: Path,
    out_dir: Path,
    missing: list[str],
) -> list[str]:
    manifests_dir = out_dir / "manifests"
    manifests_dir.mkdir(parents=True, exist_ok=True)

    manifest_sources = [
        (offline_bundle_dir / f"spt-bundle-{tag}.manifest.json", manifests_dir / "image-bundle.manifest.json", True),
        (offline_bundle_dir / f"spt-bundle-{tag}.tar.gz.sha256", manifests_dir / "image-bundle.tar.gz.sha256", False),
        (data_bundle_dir / f"spt-data-bundle-{tag}.manifest.json", manifests_dir / "data-bundle.manifest.json", False),
        (data_bundle_dir / f"spt-data-bundle-{tag}.source-checksums.sha256", manifests_dir / "data-source-checksums.sha256", False),
        (data_bundle_dir / f"spt-data-delta-{tag}.manifest.json", manifests_dir / "data-delta.manifest.json", False),
        (data_bundle_dir / f"spt-data-delta-{tag}.tar.gz.sha256", manifests_dir / "data-delta.tar.gz.sha256", False),
    ]

    output_paths: list[str] = []
    for src, dst, required in manifest_sources:
        if src.exists():
            copy_file(src, dst)
            output_paths.append(dst.relative_to(out_dir).as_posix())
        elif required:
            raise SystemExit(f"Required manifest not found: {src}")
        else:
            missing.append(str(src))

    return sorted(output_paths)


def classify_release_paths(paths: list[str]) -> tuple[list[str], list[str]]:
    sboms = [path for path in paths if "/sbom/" in path]
    scans = [
        path
        for path in paths
        if "/grype/" in path or "/secrets/" in path or "/osv-scanner/" in path
    ]
    return sorted(sboms), sorted(scans)


def emit_artifact_manifest(out_dir: Path, tag: str) -> str:
    manifest_path = out_dir / "manifest.json"
    cmd = [
        "python3",
        str(ROOT / "common" / "emit-artifact-manifest.py"),
        "--artifacts-dir",
        str(out_dir),
        "--output",
        str(manifest_path),
        "--job-id",
        f"platform-handoff-{tag}",
    ]
    subprocess.run(cmd, check=True)
    return manifest_path.relative_to(out_dir).as_posix()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_tar(out_dir: Path, tar_out: Path) -> None:
    tar_out.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(tar_out, "w") as tf:
        tf.add(out_dir, arcname=out_dir.name)
    (tar_out.with_suffix(tar_out.suffix + ".sha256")).write_text(
        f"{sha256(tar_out)}  {tar_out.name}\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--registry", default="registry.internal/security-platform")
    parser.add_argument("--results-dir", default="artifacts/results")
    parser.add_argument("--release-evidence-dir", required=True)
    parser.add_argument("--offline-bundle-dir", default="offline-bundles/out")
    parser.add_argument("--data-bundle-dir", default="data-bundles/out")
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--tar-out", required=True)
    args = parser.parse_args()

    results_dir = ROOT / args.results_dir
    release_evidence_dir = ROOT / args.release_evidence_dir
    offline_bundle_dir = ROOT / args.offline_bundle_dir
    data_bundle_dir = ROOT / args.data_bundle_dir
    out_dir = ROOT / args.out_dir
    tar_out = ROOT / args.tar_out

    if not release_evidence_dir.exists():
        raise SystemExit(
            f"release evidence directory not found: {release_evidence_dir}. Run make release-evidence TAG={args.tag} first."
        )

    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    missing_optional: list[str] = []
    release_paths = add_release_evidence(release_evidence_dir, out_dir)
    findings, candidate_correlations = add_normalized_results(results_dir, out_dir)
    manifests = add_bundle_manifests(args.tag, offline_bundle_dir, data_bundle_dir, out_dir, missing_optional)

    release_summary = release_evidence_dir / "release-evidence-summary.json"
    add_optional_file(release_summary, out_dir / "release-evidence" / "release-evidence-summary.json", missing_optional)

    sboms, scans = classify_release_paths(release_paths)

    contract = {
        "schema_version": "1.0.0",
        "contract_type": "platform-handoff-bundle",
        "contract_version": CONTRACT_VERSION,
        "generated_at": utc_now(),
        "tag": args.tag,
        "registry": args.registry,
        "artifact_manifest": "manifest.json",
        "sections": {
            "normalized_findings": sorted(findings),
            "candidate_correlations": sorted(candidate_correlations),
            "release_evidence": sorted(release_paths),
            "sboms": sboms,
            "scans": scans,
            "manifests": sorted(manifests),
        },
        "missing_optional": sorted(set(missing_optional)),
    }
    contract_path = out_dir / "platform-handoff-contract.json"
    contract_path.write_text(json.dumps(contract, indent=2) + "\n", encoding="utf-8")

    artifact_manifest_rel = emit_artifact_manifest(out_dir, args.tag)
    contract["artifact_manifest"] = artifact_manifest_rel
    contract_path.write_text(json.dumps(contract, indent=2) + "\n", encoding="utf-8")

    write_tar(out_dir, tar_out)

    print(f"Platform handoff contract: {contract_path}")
    print(f"Platform handoff directory: {out_dir}")
    print(f"Platform handoff tar: {tar_out}")
    print(f"Optional missing inputs: {len(contract['missing_optional'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
