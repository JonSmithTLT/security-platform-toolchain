#!/usr/bin/env python3
"""
common/emit-job-report.py
Validate and write a JSON job-report that conforms to schemas/job-report.schema.json.

Usage:
    emit-job-report.py [OPTIONS]

Options:
    --schema PATH         Path to job-report.schema.json
                          (default: /usr/local/share/spt/schemas/job-report.schema.json)
    --output PATH         Output file path
                          (default: $ARTIFACTS_DIR/job-report.json)
    --tool NAME           Tool name (overrides SPT_TOOL env var)
    --job-id ID           Job identifier (overrides JOB_ID env var)
    --status STATUS       Job status: success | failure | error (overrides SPT_STATUS)
    --results-file PATH   Path to a tool-result JSON file to embed
    --manifest-file PATH  Path to an artifact-manifest JSON file to embed
    --extra KEY=VALUE     Extra top-level fields (may be repeated)

Environment variables (all overridable by CLI flags):
    JOB_ID        — unique identifier for this pipeline run
    SPT_TOOL      — tool name (e.g. semgrep, codeql)
    SPT_STATUS    — success | failure | error
    ARTIFACTS_DIR — directory where job-report.json is written (default: /artifacts)
    SPT_SCHEMA    — path to job-report.schema.json
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import sys
import warnings
from pathlib import Path
from typing import Any

warnings.filterwarnings("ignore", category=DeprecationWarning)


# ── Optional jsonschema validation ─────────────────────────────────────────
try:
    import jsonschema  # type: ignore
    _HAS_JSONSCHEMA = True
except ImportError:
    _HAS_JSONSCHEMA = False


def _load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def _utc_now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _schema_store(schema_dir: Path) -> dict[str, Any]:
    store: dict[str, Any] = {}
    for schema_file in schema_dir.glob("*.schema.json"):
        schema = _load_json(schema_file)
        store[schema_file.name] = schema
        store[(schema_dir.resolve().as_uri() + "/" + schema_file.name)] = schema
        if "$id" in schema:
            store[schema["$id"]] = schema
    return store


def _validate(instance: dict, schema_path: Path) -> None:
    if not _HAS_JSONSCHEMA:
        print(
            "[WARN] jsonschema not installed; skipping schema validation.",
            file=sys.stderr,
        )
        return
    schema = _load_json(schema_path)
    schema_dir = schema_path.parent
    resolver = jsonschema.RefResolver(
        base_uri=schema_dir.resolve().as_uri() + "/",
        referrer=schema,
        store=_schema_store(schema_dir),
    )
    validator = jsonschema.Draft7Validator(schema, resolver=resolver)
    errors = validator.iter_errors(instance)
    error = jsonschema.exceptions.best_match(errors)
    if error is not None:
        raise error


def _coerce_extra_value(value: str) -> Any:
    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if lowered == "null":
        return None
    try:
        return int(value)
    except ValueError:
        pass
    try:
        return float(value)
    except ValueError:
        return value


def _parse_extra(pairs: list[str]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for pair in pairs or []:
        if "=" not in pair:
            raise ValueError(f"--extra must be KEY=VALUE, got: {pair!r}")
        k, _, v = pair.partition("=")
        result[k.strip()] = _coerce_extra_value(v)
    return result


def build_report(
    *,
    tool: str,
    job_id: str,
    status: str,
    results: Any | None,
    manifest: Any | None,
    extra: dict[str, Any],
) -> dict:
    report: dict[str, Any] = {
        "schema_version": "1.0.0",
        "job_id": job_id,
        "tool": tool,
        "status": status,
        "timestamp": _utc_now(),
    }
    if results is not None:
        report["results"] = results
    if manifest is not None:
        report["artifact_manifest"] = manifest
    report.update(extra)
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate and write a JSON job-report.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--schema",
        default=os.environ.get(
            "SPT_SCHEMA",
            "/usr/local/share/spt/schemas/job-report.schema.json",
        ),
        help="Path to job-report.schema.json",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Output path for job-report.json (default: $ARTIFACTS_DIR/job-report.json)",
    )
    parser.add_argument("--tool", default=os.environ.get("SPT_TOOL", ""))
    parser.add_argument("--job-id", default=os.environ.get("JOB_ID", "unknown"))
    parser.add_argument(
        "--status",
        default=os.environ.get("SPT_STATUS", "success"),
        choices=["success", "failure", "error"],
    )
    parser.add_argument("--results-file", default=None, help="Path to tool-result JSON")
    parser.add_argument(
        "--manifest-file", default=None, help="Path to artifact-manifest JSON"
    )
    parser.add_argument(
        "--extra",
        action="append",
        metavar="KEY=VALUE",
        default=[],
        help="Extra top-level fields (repeatable)",
    )
    args = parser.parse_args(argv)

    # ── Resolve output path ────────────────────────────────────────────────
    if args.output:
        output_path = Path(args.output)
    else:
        artifacts_dir = os.environ.get("ARTIFACTS_DIR", "/artifacts")
        output_path = Path(artifacts_dir) / "job-report.json"

    output_path.parent.mkdir(parents=True, exist_ok=True)

    # ── Load optional embedded files ───────────────────────────────────────
    results = _load_json(Path(args.results_file)) if args.results_file else None
    manifest = _load_json(Path(args.manifest_file)) if args.manifest_file else None

    # ── Build report ───────────────────────────────────────────────────────
    extra = _parse_extra(args.extra)
    report = build_report(
        tool=args.tool,
        job_id=args.job_id,
        status=args.status,
        results=results,
        manifest=manifest,
        extra=extra,
    )

    # ── Validate against schema ────────────────────────────────────────────
    schema_path = Path(args.schema)
    if schema_path.exists():
        _validate(report, schema_path)
    else:
        print(
            f"[WARN] Schema not found at {schema_path}; skipping validation.",
            file=sys.stderr,
        )

    # ── Write output ───────────────────────────────────────────────────────
    with output_path.open("w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")

    print(f"[INFO] Job report written to {output_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
