#!/usr/bin/env python3
"""Thin local/offline runner for SPT container workflows."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Any

import jsonschema
import yaml


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "schemas" / "pipeline.schema.json"
REDACT_KEYS = ("TOKEN", "PASSWORD", "PASS", "SECRET", "KEY")


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    if not isinstance(data, dict):
        raise SystemExit(f"pipeline must be a mapping: {path}")
    return data


def validate_pipeline(data: dict[str, Any]) -> None:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    jsonschema.Draft7Validator(schema).validate(data)
    ids = [step["id"] for step in data["steps"]]
    if len(ids) != len(set(ids)):
        raise SystemExit("step ids must be unique")
    known = set(ids)
    for step in data["steps"]:
        for dep in step.get("depends_on", []):
            if dep not in known:
                raise SystemExit(f"step {step['id']} depends on unknown step {dep}")
        network = step.get("network", {})
        if network.get("mode") == "enabled" and not network.get("reason"):
            raise SystemExit(f"step {step['id']} enables network without a reason")


def topo_steps(steps: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_id = {step["id"]: step for step in steps}
    ordered: list[dict[str, Any]] = []
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(step_id: str) -> None:
        if step_id in visited:
            return
        if step_id in visiting:
            raise SystemExit(f"dependency cycle includes {step_id}")
        visiting.add(step_id)
        for dep in by_id[step_id].get("depends_on", []):
            visit(dep)
        visiting.remove(step_id)
        visited.add(step_id)
        ordered.append(by_id[step_id])

    for step in steps:
        visit(step["id"])
    return ordered


def resolve_path(path: str, base: Path) -> Path:
    candidate = Path(path)
    if not candidate.is_absolute():
        candidate = base / candidate
    return candidate.resolve()


def image_ref(image: str, runtime: dict[str, Any]) -> str:
    if "/" in image or ":" in image:
        return image
    registry = runtime.get("registry", "registry.internal/security-platform")
    tag = runtime.get("tag", "latest")
    return f"{registry}/{image}:{tag}"


def step_dir(artifacts_root: Path, index: int, step_id: str) -> Path:
    return artifacts_root / "steps" / f"{index:02d}-{step_id}"


def sanitized_env(env: dict[str, str]) -> dict[str, str]:
    result = {}
    for key, value in env.items():
        if any(token in key.upper() for token in REDACT_KEYS):
            result[key] = "<redacted>"
        else:
            result[key] = value
    return result


def container_path_to_host(path: str, mounts: list[dict[str, str]], base: Path) -> Path | None:
    matches = []
    for mount in mounts:
        target = mount["target"].rstrip("/") or "/"
        if path == target or path.startswith(target + "/"):
            matches.append((len(target), mount))
    if not matches:
        return None
    _, mount = sorted(matches, key=lambda item: item[0], reverse=True)[0]
    target = mount["target"].rstrip("/") or "/"
    suffix = path[len(target):].lstrip("/")
    return resolve_path(mount["source"], base) / suffix


def prepare_mounts(mounts: list[dict[str, str]], base: Path) -> None:
    for mount in mounts:
        source = resolve_path(mount["source"], base)
        if mount.get("mode", "ro") == "rw":
            source.mkdir(parents=True, exist_ok=True)
        elif not source.exists():
            raise SystemExit(f"read-only mount source does not exist: {source}")


def docker_cmd(
    step: dict[str, Any],
    runtime: dict[str, Any],
    env: dict[str, str],
    mounts: list[dict[str, str]],
    base: Path,
) -> list[str]:
    network = step.get("network", {}).get("mode", runtime.get("default_network", "none"))
    cmd = ["docker", "run", "--rm"]
    if network == "none":
        cmd.extend(["--network", "none"])
    for key, value in env.items():
        cmd.extend(["-e", f"{key}={value}"])
    for mount in mounts:
        source = resolve_path(mount["source"], base)
        mode = mount.get("mode", "ro")
        cmd.extend(["-v", f"{source}:{mount['target']}:{mode}"])
    cmd.append(image_ref(step["image"], runtime))
    cmd.extend(step["command"])
    return cmd


def inspect_image_digest(ref: str) -> str:
    proc = subprocess.run(
        ["docker", "image", "inspect", ref, "--format", "{{json .RepoDigests}}"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if proc.returncode != 0:
        return ""
    try:
        digests = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return ""
    return digests[0] if digests else ""


def validate_json_schema(path: Path, schema_path: Path) -> list[str]:
    instance = json.loads(path.read_text(encoding="utf-8"))
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    resolver = jsonschema.RefResolver(
        base_uri=(ROOT / "schemas").resolve().as_uri() + "/",
        referrer=schema,
    )
    validator = jsonschema.Draft7Validator(schema, resolver=resolver)
    return [error.message for error in sorted(validator.iter_errors(instance), key=lambda err: list(err.path))]


def run_pipeline(path: Path, dry_run: bool = False) -> int:
    base = path.parent.resolve()
    pipeline = load_yaml(path)
    validate_pipeline(pipeline)
    runtime = pipeline.get("runtime", {})
    artifacts_root = resolve_path(pipeline["artifacts_root"], base)
    run_id = f"pipe_{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:8]}"
    request_id = pipeline.get("request_correlation_id")
    if not request_id or request_id == "auto":
        request_id = f"req_{uuid.uuid4().hex[:12]}"

    artifacts_root.mkdir(parents=True, exist_ok=True)
    logs_dir = artifacts_root / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)

    report: dict[str, Any] = {
        "pipeline_schema_version": "0.1",
        "pipeline_id": pipeline["pipeline_id"],
        "run_id": run_id,
        "request_correlation_id": request_id,
        "started_at": utc_now(),
        "status": "running",
        "dry_run": dry_run,
        "steps": [],
    }

    failed_steps: set[str] = set()
    for index, step in enumerate(topo_steps(pipeline["steps"]), start=1):
        sid = step["id"]
        deps = step.get("depends_on", [])
        step_artifacts = step_dir(artifacts_root, index, sid)
        step_artifacts.mkdir(parents=True, exist_ok=True)
        mounts = list(step.get("mounts", []))
        env = {key: str(value) for key, value in step.get("env", {}).items()}
        env.setdefault("JOB_ID", sid)
        env["REQUEST_CORRELATION_ID"] = request_id
        env.setdefault("ARTIFACTS_DIR", "/artifacts")

        started = utc_now()
        ref = image_ref(step["image"], runtime)
        network = step.get("network", {}).get("mode", runtime.get("default_network", "none"))
        step_report: dict[str, Any] = {
            "id": sid,
            "status": "pending",
            "image": ref,
            "image_digest": "" if dry_run else inspect_image_digest(ref),
            "command": step["command"],
            "env": sanitized_env(env),
            "network": network,
            "exit_code": None,
            "artifacts_dir": str(step_artifacts.relative_to(artifacts_root)),
            "expected_artifacts_present": False,
            "schema_validation_status": "not_run",
            "started_at": started,
        }

        if any(dep in failed_steps for dep in deps):
            step_report["status"] = "skipped"
            step_report["finished_at"] = utc_now()
            report["steps"].append(step_report)
            failed_steps.add(sid)
            continue

        try:
            prepare_mounts(mounts, base)
            cmd = docker_cmd(step, runtime, env, mounts, base)
            step_report["docker_command"] = cmd
            stdout_path = step_artifacts / "stdout.log"
            stderr_path = step_artifacts / "stderr.log"

            if dry_run:
                step_report["status"] = "dry_run"
                step_report["exit_code"] = 0
                stdout_path.write_text(" ".join(cmd) + "\n", encoding="utf-8")
                stderr_path.write_text("", encoding="utf-8")
            else:
                with stdout_path.open("w", encoding="utf-8") as stdout, stderr_path.open("w", encoding="utf-8") as stderr:
                    proc = subprocess.run(cmd, stdout=stdout, stderr=stderr, text=True, timeout=step.get("timeout_seconds"))
                step_report["exit_code"] = proc.returncode
                step_report["status"] = "success" if proc.returncode == 0 else "failed"

            if dry_run:
                step_report["expected_artifacts_present"] = None
                step_report["schema_validation_status"] = "dry_run"
            else:
                missing = []
                for artifact in step.get("expected_artifacts", []):
                    host_path = container_path_to_host(artifact, mounts, base)
                    if host_path is None or not host_path.exists():
                        missing.append(artifact)
                step_report["missing_expected_artifacts"] = missing
                step_report["expected_artifacts_present"] = not missing
                if missing:
                    step_report["status"] = "failed"

                validations = []
                validation_failed = False
                for item in step.get("schema_validation", []):
                    host_path = container_path_to_host(item["path"], mounts, base)
                    schema_path = resolve_path(item["schema"], ROOT)
                    if host_path is None or not host_path.exists():
                        errors = [f"schema target not found: {item['path']}"]
                    else:
                        errors = validate_json_schema(host_path, schema_path)
                    validations.append({"path": item["path"], "schema": item["schema"], "valid": not errors, "errors": errors})
                    validation_failed = validation_failed or bool(errors)
                if validations:
                    step_report["schema_validations"] = validations
                    step_report["schema_validation_status"] = "failed" if validation_failed else "passed"
                    if validation_failed:
                        step_report["status"] = "failed"
        except Exception as exc:  # noqa: BLE001 - execution report should include operational errors.
            step_report["status"] = "failed"
            step_report["error"] = str(exc)

        step_report["finished_at"] = utc_now()
        report["steps"].append(step_report)
        if step_report["status"] == "failed" and (step.get("required", True) or not step.get("continue_on_failure", False)):
            failed_steps.add(sid)

    report["finished_at"] = utc_now()
    if dry_run:
        report["status"] = "dry_run"
    elif failed_steps:
        report["status"] = "failed"
    else:
        report["status"] = "success"

    write_report(artifacts_root, report)
    return 1 if report["status"] == "failed" else 0


def write_report(artifacts_root: Path, report: dict[str, Any]) -> None:
    (artifacts_root / "pipeline-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    with (artifacts_root / "pipeline-summary.md").open("w", encoding="utf-8") as fh:
        fh.write("# Pipeline Summary\n\n")
        fh.write(f"- Pipeline: `{report['pipeline_id']}`\n")
        fh.write(f"- Run ID: `{report['run_id']}`\n")
        fh.write(f"- Status: `{report['status']}`\n")
        fh.write(f"- Request correlation ID: `{report['request_correlation_id']}`\n\n")
        fh.write("| Step | Status | Exit | Expected Artifacts | Schema |\n")
        fh.write("|---|---|---:|---|---|\n")
        for step in report["steps"]:
            fh.write(
                f"| {step['id']} | {step['status']} | {step.get('exit_code')} | "
                f"{step.get('expected_artifacts_present')} | {step.get('schema_validation_status')} |\n"
            )


def summarize(path: Path) -> int:
    report_path = path / "pipeline-report.json" if path.is_dir() else path
    report = json.loads(report_path.read_text(encoding="utf-8"))
    print(f"{report['pipeline_id']} {report['run_id']} {report['status']}")
    for step in report.get("steps", []):
        print(f"- {step['id']}: {step['status']} exit={step.get('exit_code')}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="spt-pipeline")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("validate", "dry-run", "run"):
        cmd = sub.add_parser(name)
        cmd.add_argument("pipeline", type=Path)
    summary = sub.add_parser("summarize")
    summary.add_argument("path", type=Path)
    args = parser.parse_args()

    if args.command == "validate":
        validate_pipeline(load_yaml(args.pipeline))
        print(f"valid: {args.pipeline}")
        return 0
    if args.command == "dry-run":
        return run_pipeline(args.pipeline, dry_run=True)
    if args.command == "run":
        return run_pipeline(args.pipeline, dry_run=False)
    if args.command == "summarize":
        return summarize(args.path)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
