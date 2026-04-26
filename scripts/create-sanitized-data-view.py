#!/usr/bin/env python3
"""Create a sanitized copy of data-bundle sources for AV/DLP-constrained environments."""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import json
import shutil
import zipfile
from pathlib import Path
from typing import Any


REDACTED_TEXT = "[REDACTED in sanitized data bundle]"
REDACT_KEYS = {
    "details",
    "description",
    "content",
    "poc",
    "proof_of_concept",
    "exploit",
    "reproducer",
    "webshell",
    "payload",
}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def redact_json_value(value: Any, stats: dict[str, int], key_name: str | None = None) -> Any:
    if isinstance(value, dict):
        out = {}
        for key, child in value.items():
            lowered = key.lower()
            if lowered in REDACT_KEYS and isinstance(child, str) and child:
                out[key] = REDACTED_TEXT
                stats["redacted_fields"] += 1
            else:
                out[key] = redact_json_value(child, stats, lowered)
        return out

    if isinstance(value, list):
        return [redact_json_value(item, stats, key_name) for item in value]

    if isinstance(value, str) and key_name in REDACT_KEYS and value:
        stats["redacted_fields"] += 1
        return REDACTED_TEXT

    return value


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def sanitize_github_advisory_db(src: Path, dst: Path, stats: dict[str, int]) -> None:
    for path in sorted(src.rglob("*")):
        rel = path.relative_to(src)
        out_path = dst / rel
        if path.is_dir():
            out_path.mkdir(parents=True, exist_ok=True)
            continue
        if path.suffix == ".json":
            data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
            sanitized = redact_json_value(data, stats)
            write_json(out_path, sanitized)
            stats["redacted_files"] += 1
        else:
            out_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, out_path)


def sanitize_nvd(src: Path, dst: Path, stats: dict[str, int]) -> None:
    for path in sorted(src.rglob("*")):
        rel = path.relative_to(src)
        out_path = dst / rel
        if path.is_dir():
            out_path.mkdir(parents=True, exist_ok=True)
            continue
        if path.suffixes[-2:] == [".json", ".gz"]:
            with gzip.open(path, "rt", encoding="utf-8", errors="replace") as fh:
                data = json.load(fh)
            for item in data.get("vulnerabilities", []):
                cve = item.get("cve") or {}
                for description in cve.get("descriptions") or []:
                    if isinstance(description, dict) and description.get("value"):
                        description["value"] = REDACTED_TEXT
                        stats["redacted_fields"] += 1
            out_path.parent.mkdir(parents=True, exist_ok=True)
            with gzip.open(out_path, "wt", encoding="utf-8") as fh:
                json.dump(data, fh)
            stats["redacted_files"] += 1
        else:
            out_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, out_path)


def sanitize_osv(src: Path, dst: Path, stats: dict[str, int]) -> None:
    for path in sorted(src.rglob("*")):
        rel = path.relative_to(src)
        out_path = dst / rel
        if path.is_dir():
            out_path.mkdir(parents=True, exist_ok=True)
            continue
        if path.name == "all.zip":
            out_path.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(path) as in_zip, zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as out_zip:
                for name in sorted(in_zip.namelist()):
                    raw = in_zip.read(name)
                    if name.endswith(".json"):
                        data = json.loads(raw.decode("utf-8", errors="replace"))
                        sanitized = redact_json_value(data, stats)
                        out_zip.writestr(name, json.dumps(sanitized, sort_keys=True).encode("utf-8"))
                    else:
                        out_zip.writestr(name, raw)
            stats["redacted_files"] += 1
        else:
            out_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, out_path)


def sanitize_vendor_advisories(src: Path, dst: Path, stats: dict[str, int]) -> None:
    text_extensions = {".txt", ".md", ".rst", ".adoc", ".html", ".htm"}
    for path in sorted(src.rglob("*")):
        rel = path.relative_to(src)
        out_path = dst / rel
        if path.is_dir():
            out_path.mkdir(parents=True, exist_ok=True)
            continue
        out_path.parent.mkdir(parents=True, exist_ok=True)
        if path.suffix == ".json":
            data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
            sanitized = redact_json_value(data, stats)
            write_json(out_path, sanitized)
            stats["redacted_files"] += 1
        elif path.suffix.lower() in text_extensions:
            out_path.write_text(REDACTED_TEXT + "\n", encoding="utf-8")
            stats["redacted_files"] += 1
            stats["redacted_fields"] += 1
        else:
            shutil.copy2(path, out_path)


def copy_dataset(src: Path, dst: Path) -> None:
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", default="data-bundles/sources")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--report-out", required=True)
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    report_out = Path(args.report_out)

    if not input_dir.exists():
        raise SystemExit(f"input dataset directory does not exist: {input_dir}")

    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    dataset_stats: list[dict[str, Any]] = []
    handlers = {
        "github-advisory-db": sanitize_github_advisory_db,
        "nvd": sanitize_nvd,
        "osv": sanitize_osv,
        "vendor-advisories": sanitize_vendor_advisories,
    }

    for dataset_dir in sorted(path for path in input_dir.iterdir() if path.is_dir()):
        dst = output_dir / dataset_dir.name
        stats = {
            "dataset": dataset_dir.name,
            "mode": "copied",
            "redacted_files": 0,
            "redacted_fields": 0,
        }
        handler = handlers.get(dataset_dir.name)
        if handler is None:
            copy_dataset(dataset_dir, dst)
        else:
            dst.mkdir(parents=True, exist_ok=True)
            handler(dataset_dir, dst, stats)
            stats["mode"] = "redacted"
        dataset_stats.append(stats)

    report = {
        "schema_version": "1.0.0",
        "generated_at": utc_now(),
        "input_dir": str(input_dir),
        "output_dir": str(output_dir),
        "datasets": dataset_stats,
        "summary": {
            "dataset_count": len(dataset_stats),
            "redacted_dataset_count": sum(1 for item in dataset_stats if item["mode"] == "redacted"),
            "redacted_file_count": sum(int(item["redacted_files"]) for item in dataset_stats),
            "redacted_field_count": sum(int(item["redacted_fields"]) for item in dataset_stats),
        },
    }
    report_out.parent.mkdir(parents=True, exist_ok=True)
    report_out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(f"Sanitized data directory: {output_dir}")
    print(f"Sanitization report: {report_out}")
    print(f"Redacted datasets: {report['summary']['redacted_dataset_count']}")
    print(f"Redacted files: {report['summary']['redacted_file_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())