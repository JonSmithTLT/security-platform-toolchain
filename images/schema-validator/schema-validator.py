#!/usr/bin/env python3
"""Validate SPT JSON artifacts against repository schemas."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import warnings
from pathlib import Path
from typing import Any

import jsonschema

warnings.filterwarnings("ignore", category=DeprecationWarning)


SCHEMA_BY_NAME = {
    "job-report.json": "job-report.schema.json",
    "manifest.json": "artifact-manifest.schema.json",
    "tool-result.json": "tool-result.schema.json",
    "harness-manifest.json": "harness-manifest.schema.json",
    "fuzz-campaign.json": "fuzz-campaign.schema.json",
    "crashes.json": "crashes.schema.json",
    "crash-triage.json": "crash-triage.schema.json",
    "protocol-campaign.json": "protocol-campaign.schema.json",
    "replay-result.json": "replay-result.schema.json",
    "corpus-summary.json": "corpus-summary.schema.json",
}


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def schema_store(schemas_dir: Path) -> dict[str, Any]:
    store: dict[str, Any] = {}
    for schema_file in schemas_dir.glob("*.schema.json"):
        schema = load_json(schema_file)
        store[schema_file.name] = schema
        store[(schemas_dir.resolve().as_uri() + "/" + schema_file.name)] = schema
        if "$id" in schema:
            store[schema["$id"]] = schema
    return store


def schema_for(path: Path) -> str | None:
    if path.name in SCHEMA_BY_NAME:
        return SCHEMA_BY_NAME[path.name]
    return None


def candidate_files(target: Path) -> list[Path]:
    if target.is_file():
        return [target]
    files: list[Path] = []
    for name in ("job-report.json", "manifest.json"):
        path = target / name
        if path.exists():
            files.append(path)
    files.extend(sorted((target / "results").glob("*/tool-result.json")))
    for path in sorted((target / "results").glob("*/normalized/*.json")):
        if schema_for(path):
            files.append(path)
    return files


def make_finding(path: Path, schema_name: str, message: str, index: int) -> dict[str, Any]:
    return {
        "id": f"schema-validation-{index}",
        "title": "Artifact failed schema validation",
        "severity": "high",
        "rule_id": schema_name,
        "location": {"file": str(path)},
        "message": message,
    }


def validate_file(path: Path, schemas_dir: Path) -> tuple[str, list[str]]:
    schema_name = schema_for(path)
    if schema_name is None:
        return "skipped", []

    schema_path = schemas_dir / schema_name
    instance = load_json(path)
    schema = load_json(schema_path)
    resolver = jsonschema.RefResolver(
        base_uri=schemas_dir.resolve().as_uri() + "/",
        referrer=schema,
        store=schema_store(schemas_dir),
    )
    validator = jsonschema.Draft7Validator(schema, resolver=resolver)
    errors = sorted(validator.iter_errors(instance), key=lambda err: list(err.path))
    return schema_name, [error.message for error in errors]


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate SPT artifact JSON files.")
    parser.add_argument("--target", required=True)
    parser.add_argument("--schemas-dir", required=True)
    parser.add_argument("--summary-out", required=True)
    parser.add_argument("--tool-result-out", required=True)
    args = parser.parse_args()

    target = Path(args.target)
    schemas_dir = Path(args.schemas_dir)
    summary_out = Path(args.summary_out)
    tool_result_out = Path(args.tool_result_out)

    files = candidate_files(target)
    findings: list[dict[str, Any]] = []
    validations: list[dict[str, Any]] = []

    for path in files:
        schema_name = schema_for(path)
        if schema_name is None:
            continue
        try:
            resolved_schema, errors = validate_file(path, schemas_dir)
        except Exception as exc:  # noqa: BLE001 - include parse/schema errors as findings.
            errors = [str(exc)]
            resolved_schema = schema_name

        relative_path = str(path)
        validations.append(
            {
                "path": relative_path,
                "schema": resolved_schema,
                "valid": not errors,
                "errors": errors,
            }
        )
        for message in errors:
            findings.append(make_finding(path, resolved_schema, message, len(findings) + 1))

    summary = {
        "schema_version": "1.0.0",
        "generated_at": utc_now(),
        "target": str(target),
        "validated_count": len(validations),
        "error_count": len(findings),
        "validations": validations,
    }
    tool_result = {
        "schema_version": "1.0.0",
        "tool": "schema-validator",
        "target": str(target),
        "summary": {
            "total": len(findings),
            "critical": 0,
            "high": len(findings),
            "medium": 0,
            "low": 0,
            "info": 0,
        },
        "findings": findings,
    }

    summary_out.parent.mkdir(parents=True, exist_ok=True)
    tool_result_out.parent.mkdir(parents=True, exist_ok=True)
    summary_out.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    tool_result_out.write_text(json.dumps(tool_result, indent=2) + "\n", encoding="utf-8")

    print(f"validated={len(validations)} errors={len(findings)}", file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
