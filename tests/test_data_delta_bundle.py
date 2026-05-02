from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "create-data-delta-bundle.py"


def load_delta_module():
    spec = importlib.util.spec_from_file_location("create_data_delta_bundle", SCRIPT)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_delta(data_dir: Path, base_sums: Path, out: Path, manifest: Path) -> dict:
    subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--data-dir",
            str(data_dir),
            "--base-source-checksums",
            str(base_sums),
            "--out",
            str(out),
            "--manifest-out",
            str(manifest),
            "--tag",
            "test",
        ],
        check=True,
    )
    return json.loads(manifest.read_text(encoding="utf-8"))


def test_delta_bundle_writes_gzip_when_output_ends_with_gz(tmp_path: Path) -> None:
    data_dir = tmp_path / "sources"
    dataset = data_dir / "nvd"
    dataset.mkdir(parents=True)
    (dataset / "one.json").write_text("one", encoding="utf-8")

    base_sums = tmp_path / "base.sha256"
    base_sums.write_text("", encoding="utf-8")
    out = tmp_path / "delta.tar.gz"
    manifest_path = tmp_path / "delta.manifest.json"

    manifest = run_delta(data_dir, base_sums, out, manifest_path)

    assert out.read_bytes()[:2] == b"\x1f\x8b"
    assert manifest["checksum_mode"] == "file"
    assert manifest["summary"]["included_files"] == 1


def test_dataset_checksum_mode_includes_changed_dataset_only(tmp_path: Path) -> None:
    delta = load_delta_module()
    data_dir = tmp_path / "sources"
    nvd = data_dir / "nvd"
    osv = data_dir / "osv"
    nvd.mkdir(parents=True)
    osv.mkdir()
    (nvd / "metadata.json").write_text('{"source": "nvd"}', encoding="utf-8")
    (nvd / "SHA256SUMS").write_text("old  old.json\n", encoding="utf-8")
    (nvd / "current.json").write_text("current", encoding="utf-8")
    (osv / "metadata.json").write_text('{"source": "osv"}', encoding="utf-8")
    (osv / "SHA256SUMS").write_text("same  same.json\n", encoding="utf-8")
    (osv / "current.json").write_text("current", encoding="utf-8")

    base_sums = tmp_path / "base.sha256"
    base_sums.write_text(
        "\n".join(
            [
                "definitely-different  ./nvd",
                f"{delta.dataset_digest(osv)}  ./osv",
                "",
            ]
        ),
        encoding="utf-8",
    )
    out = tmp_path / "delta.tar.gz"
    manifest_path = tmp_path / "delta.manifest.json"

    manifest = run_delta(data_dir, base_sums, out, manifest_path)

    assert manifest["checksum_mode"] == "dataset"
    assert manifest["modified"] == ["nvd"]
    assert manifest["removed"] == []
    assert manifest["summary"]["included_files"] == 2
