#!/usr/bin/env python3
"""Convert common raw security tool outputs to SPT tool-result JSON."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Callable


SEVERITIES = {"critical", "high", "medium", "low", "info"}
SARIF_SCHEMA = "https://json.schemastore.org/sarif-2.1.0.json"


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def severity(value: Any, default: str = "info") -> str:
    text = str(value or default).lower()
    aliases = {
        "error": "high",
        "warning": "medium",
        "warn": "medium",
        "note": "info",
        "unknown": "info",
    }
    text = aliases.get(text, text)
    return text if text in SEVERITIES else default


def stable_id(*parts: Any) -> str:
    digest = hashlib.sha256("|".join(str(part) for part in parts).encode("utf-8")).hexdigest()
    return digest[:16]


def location(path: Any = None, start: Any = None, end: Any = None, col: Any = None) -> dict[str, Any]:
    loc: dict[str, Any] = {}
    if path:
        loc["file"] = str(path)
    if isinstance(start, int) and start > 0:
        loc["line_start"] = start
    if isinstance(end, int) and end > 0:
        loc["line_end"] = end
    if isinstance(col, int) and col >= 0:
        loc["col_start"] = col
    return loc


def summarize(findings: list[dict[str, Any]]) -> dict[str, int]:
    summary = {"total": len(findings), "critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0}
    for finding in findings:
        sev = severity(finding.get("severity"))
        summary[sev] += 1
    return summary


def sarif_level(value: Any) -> str:
    sev = severity(value)
    if sev in {"critical", "high"}:
        return "error"
    if sev == "medium":
        return "warning"
    return "note"


def tool_result(tool: str, target: str, findings: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "schema_version": "1.0.0",
        "tool": tool,
        "target": target,
        "summary": summarize(findings),
        "findings": findings,
    }


def tool_result_to_sarif(result: dict[str, Any]) -> dict[str, Any]:
    tool = str(result.get("tool") or "spt")
    rules: dict[str, dict[str, Any]] = {}
    sarif_results = []

    for finding in result.get("findings", []):
        if not isinstance(finding, dict):
            continue
        rule_id = str(finding.get("rule_id") or "spt-finding")
        title = str(finding.get("title") or rule_id)
        rules.setdefault(
            rule_id,
            {
                "id": rule_id,
                "shortDescription": {"text": title},
                "defaultConfiguration": {"level": sarif_level(finding.get("severity"))},
                "properties": {"sptSeverity": severity(finding.get("severity"))},
            },
        )

        sarif_result: dict[str, Any] = {
            "ruleId": rule_id,
            "level": sarif_level(finding.get("severity")),
            "message": {"text": str(finding.get("message") or title)},
            "properties": {
                "sptFindingId": finding.get("id"),
                "sptSeverity": severity(finding.get("severity")),
            },
        }
        if finding.get("cve"):
            sarif_result["properties"]["cve"] = finding.get("cve")
        if finding.get("references"):
            sarif_result["properties"]["references"] = finding.get("references")

        loc = finding.get("location") or {}
        file_path = loc.get("file") if isinstance(loc, dict) else None
        if file_path:
            region: dict[str, Any] = {}
            if loc.get("line_start"):
                region["startLine"] = loc["line_start"]
            if loc.get("line_end"):
                region["endLine"] = loc["line_end"]
            if loc.get("col_start"):
                region["startColumn"] = loc["col_start"]
            sarif_result["locations"] = [
                {
                    "physicalLocation": {
                        "artifactLocation": {"uri": str(file_path)},
                        "region": region,
                    }
                }
            ]

        sarif_results.append(sarif_result)

    return {
        "version": "2.1.0",
        "$schema": SARIF_SCHEMA,
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": tool,
                        "rules": sorted(rules.values(), key=lambda item: item["id"]),
                    }
                },
                "results": sarif_results,
                "properties": {
                    "sptSchemaVersion": result.get("schema_version"),
                    "sptTarget": result.get("target"),
                },
            }
        ],
    }


def normalize_semgrep(path: Path) -> tuple[str, dict[str, Any]]:
    data = load_json(path)
    findings = []
    for item in data.get("results", []):
        extra = item.get("extra", {})
        start = item.get("start", {})
        end = item.get("end", {})
        check_id = item.get("check_id", "semgrep")
        findings.append(
            {
                "id": stable_id("semgrep", check_id, item.get("path"), start.get("line")),
                "title": extra.get("message") or check_id,
                "severity": severity(extra.get("severity")),
                "rule_id": check_id,
                "location": location(item.get("path"), start.get("line"), end.get("line"), start.get("col")),
                "message": extra.get("message") or "",
                "raw": item,
            }
        )
    return "semgrep", tool_result("semgrep", str(path), findings)


def normalize_sarif(path: Path) -> tuple[str, dict[str, Any]]:
    data = load_json(path)
    findings = []
    tool_name = "sarif"
    for run in data.get("runs", []):
        tool_name = run.get("tool", {}).get("driver", {}).get("name", tool_name)
        rules = {
            rule.get("id"): rule
            for rule in run.get("tool", {}).get("driver", {}).get("rules", [])
            if isinstance(rule, dict)
        }
        for result in run.get("results", []):
            rule_id = result.get("ruleId", "sarif")
            rule = rules.get(rule_id, {})
            region = {}
            artifact = None
            locations = result.get("locations") or []
            if locations:
                physical = locations[0].get("physicalLocation", {})
                artifact = physical.get("artifactLocation", {}).get("uri")
                region = physical.get("region", {})
            level = result.get("level") or rule.get("defaultConfiguration", {}).get("level")
            title = rule.get("shortDescription", {}).get("text") or result.get("message", {}).get("text") or rule_id
            findings.append(
                {
                    "id": stable_id(tool_name, rule_id, artifact, region.get("startLine")),
                    "title": title,
                    "severity": severity(level),
                    "rule_id": rule_id,
                    "location": location(
                        artifact,
                        region.get("startLine"),
                        region.get("endLine"),
                        region.get("startColumn"),
                    ),
                    "message": result.get("message", {}).get("text", ""),
                    "raw": result,
                }
            )
    return tool_name.lower(), tool_result(tool_name.lower(), str(path), findings)


def normalize_gitleaks(path: Path) -> tuple[str, dict[str, Any]]:
    data = load_json(path)
    findings = []
    for item in data if isinstance(data, list) else []:
        rule_id = item.get("RuleID") or item.get("rule") or "gitleaks"
        file_path = item.get("File") or item.get("file")
        line = item.get("StartLine") or item.get("line")
        findings.append(
            {
                "id": stable_id("gitleaks", rule_id, file_path, line, item.get("Secret")),
                "title": item.get("Description") or f"Secret matched {rule_id}",
                "severity": "high",
                "rule_id": rule_id,
                "location": location(file_path, line, item.get("EndLine")),
                "message": item.get("Description") or "",
                "raw": item,
            }
        )
    return "gitleaks", tool_result("gitleaks", str(path), findings)


def normalize_osv(path: Path) -> tuple[str, dict[str, Any]]:
    data = load_json(path)
    findings = []
    results = data.get("results", []) if isinstance(data, dict) else []
    for result in results:
        package = result.get("package", {})
        for vuln in result.get("vulnerabilities", []):
            vuln_id = vuln.get("id") or "osv"
            findings.append(
                {
                    "id": stable_id("osv", package.get("name"), vuln_id),
                    "title": vuln.get("summary") or vuln_id,
                    "severity": severity(vuln.get("database_specific", {}).get("severity"), "medium"),
                    "rule_id": vuln_id,
                    "cve": next((alias for alias in vuln.get("aliases", []) if str(alias).startswith("CVE-")), None),
                    "message": vuln.get("details") or vuln.get("summary") or "",
                    "references": [ref.get("url") for ref in vuln.get("references", []) if ref.get("url")],
                    "raw": {"package": package, "vulnerability": vuln},
                }
            )
    return "osv-scanner", tool_result("osv-scanner", str(path), findings)


def normalize_jsonl(path: Path, tool: str) -> tuple[str, dict[str, Any]]:
    findings = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            item = {"line": line}
        rule_id = item.get("DetectorName") or item.get("SourceName") or tool
        findings.append(
            {
                "id": stable_id(tool, line_number, item),
                "title": item.get("DetectorName") or item.get("reason") or f"{tool} finding",
                "severity": "high" if tool == "trufflehog" else "info",
                "rule_id": rule_id,
                "message": item.get("Raw") or item.get("Redacted") or "",
                "raw": item,
            }
        )
    return tool, tool_result(tool, str(path), findings)


def normalize_sanitizer(path: Path) -> tuple[str, dict[str, Any]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    findings = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        if "ERROR:" not in line or "Sanitizer" not in line:
            continue
        title = line.split("ERROR:", 1)[1].strip() or "Sanitizer finding"
        findings.append(
            {
                "id": stable_id("sanitizer", path, line_number, line),
                "title": title[:160],
                "severity": "high",
                "rule_id": "sanitizer-error",
                "location": location(str(path), line_number),
                "message": line.strip(),
                "raw": {"line": line, "line_number": line_number},
            }
        )
    return "sanitizer", tool_result("sanitizer", str(path), findings)


def normalize_valgrind_xml(path: Path) -> tuple[str, dict[str, Any]]:
    root = ET.parse(path).getroot()
    findings = []
    for index, error in enumerate(root.findall(".//error"), start=1):
        kind = (error.findtext("kind") or "valgrind-error").strip()
        what = (error.findtext("what") or error.findtext("xwhat/text") or kind).strip()
        frame = error.find(".//stack/frame")
        file_path = frame.findtext("file") if frame is not None else None
        line_text = frame.findtext("line") if frame is not None else None
        line = int(line_text) if line_text and line_text.isdigit() else None
        findings.append(
            {
                "id": stable_id("valgrind", kind, what, file_path, line, index),
                "title": what[:160],
                "severity": "high" if "Leak" not in kind else "medium",
                "rule_id": kind,
                "location": location(file_path, line),
                "message": what,
                "raw": {"kind": kind, "what": what},
            }
        )
    return "valgrind", tool_result("valgrind", str(path), findings)


def normalize_valgrind_text(path: Path) -> tuple[str, dict[str, Any]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    findings = []
    markers = ("Invalid read", "Invalid write", "Use of uninitialised", "definitely lost")
    for line_number, line in enumerate(text.splitlines(), start=1):
        if not any(marker in line for marker in markers):
            continue
        findings.append(
            {
                "id": stable_id("valgrind", path, line_number, line),
                "title": line.strip()[:160],
                "severity": "high" if "Invalid" in line else "medium",
                "rule_id": "valgrind-text",
                "location": location(str(path), line_number),
                "message": line.strip(),
                "raw": {"line": line, "line_number": line_number},
            }
        )
    return "valgrind", tool_result("valgrind", str(path), findings)


def normalize_afl_crash(path: Path) -> tuple[str, dict[str, Any]]:
    finding = {
        "id": stable_id("afl", path.name),
        "title": f"AFL crash input: {path.name}",
        "severity": "high",
        "rule_id": "afl-crash",
        "location": location(str(path)),
        "message": f"Crash artifact discovered at {path}",
        "raw": {"path": str(path), "size_bytes": path.stat().st_size if path.exists() else 0},
    }
    return "afl", tool_result("afl", str(path), [finding])


def detect(path: Path, requested: str) -> str:
    if requested != "auto":
        return requested
    name = path.name.lower()
    if name.endswith(".sarif"):
        return "sarif"
    if name == "semgrep.json":
        return "semgrep"
    if name == "gitleaks.json":
        return "gitleaks"
    if name == "trufflehog.jsonl":
        return "trufflehog"
    if "osv" in name and name.endswith(".json"):
        return "osv"
    if name.endswith(".xml") and "valgrind" in name:
        return "valgrind-xml"
    if "valgrind" in name and (name.endswith(".log") or name.endswith(".txt")):
        return "valgrind-text"
    if "sanitizer" in name or name.startswith(("asan", "ubsan", "tsan", "msan")):
        return "sanitizer"
    if name.startswith("id:") or name.startswith("id_"):
        return "afl-crash"
    return "unknown"


NORMALIZERS: dict[str, Callable[[Path], tuple[str, dict[str, Any]]]] = {
    "semgrep": normalize_semgrep,
    "sarif": normalize_sarif,
    "codeql": normalize_sarif,
    "gitleaks": normalize_gitleaks,
    "osv": normalize_osv,
    "trufflehog": lambda path: normalize_jsonl(path, "trufflehog"),
    "sanitizer": normalize_sanitizer,
    "valgrind-xml": normalize_valgrind_xml,
    "valgrind-text": normalize_valgrind_text,
    "afl-crash": normalize_afl_crash,
}


def candidate_files(root: Path) -> list[Path]:
    if root.is_file():
        return [root]
    patterns = (
        "*/raw/*.sarif",
        "*/raw/semgrep.json",
        "*/raw/gitleaks.json",
        "*/raw/trufflehog.jsonl",
        "*/raw/*osv*.json",
        "*/raw/*valgrind*.xml",
        "*/raw/*valgrind*.log",
        "*/raw/*valgrind*.txt",
        "*/raw/*sanitizer*.log",
        "*/raw/*sanitizer*.txt",
        "*/raw/afl-out/*/crashes/id*",
    )
    files: list[Path] = []
    for pattern in patterns:
        files.extend(root.glob(pattern))
    return sorted(set(files))


def output_path_for(raw_path: Path, artifacts_dir: Path | None, explicit: str | None) -> Path:
    if explicit:
        return Path(explicit)
    if raw_path.parent.name == "raw":
        return raw_path.parent.parent / "tool-result.json"
    if artifacts_dir:
        return artifacts_dir / "results" / raw_path.stem / "tool-result.json"
    return raw_path.with_suffix(".tool-result.json")


def main() -> int:
    parser = argparse.ArgumentParser(description="Normalize raw tool output to SPT tool-result JSON.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--format", default="auto")
    parser.add_argument("--output", default="")
    parser.add_argument("--summary-out", required=True)
    parser.add_argument("--aggregate-out", required=True)
    parser.add_argument("--sarif-out", default="")
    args = parser.parse_args()

    input_path = Path(args.input)
    files = candidate_files(input_path)
    artifacts_dir = Path("/artifacts")
    normalized = []
    errors = []
    aggregate_findings: list[dict[str, Any]] = []

    for raw_path in files:
        fmt = detect(raw_path, args.format)
        normalizer = NORMALIZERS.get(fmt)
        if normalizer is None:
            continue
        try:
            tool, result = normalizer(raw_path)
            out_path = output_path_for(raw_path, artifacts_dir, args.output if input_path.is_file() else None)
            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
            normalized.append({"input": str(raw_path), "output": str(out_path), "tool": tool, "findings": len(result["findings"])})
            for finding in result["findings"]:
                copied = dict(finding)
                copied["raw_source"] = str(raw_path)
                aggregate_findings.append(copied)
        except Exception as exc:  # noqa: BLE001 - capture normalizer failure as summary data.
            errors.append({"input": str(raw_path), "error": str(exc)})

    summary = {
        "schema_version": "1.0.0",
        "generated_at": utc_now(),
        "input": str(input_path),
        "normalized_count": len(normalized),
        "finding_count": len(aggregate_findings),
        "error_count": len(errors),
        "normalized": normalized,
        "errors": errors,
    }
    aggregate = tool_result("result-normalizers", str(input_path), aggregate_findings)

    summary_out = Path(args.summary_out)
    aggregate_out = Path(args.aggregate_out)
    summary_out.parent.mkdir(parents=True, exist_ok=True)
    aggregate_out.parent.mkdir(parents=True, exist_ok=True)
    summary_out.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    aggregate_out.write_text(json.dumps(aggregate, indent=2) + "\n", encoding="utf-8")
    if args.sarif_out:
        sarif_out = Path(args.sarif_out)
        sarif_out.parent.mkdir(parents=True, exist_ok=True)
        sarif_out.write_text(json.dumps(tool_result_to_sarif(aggregate), indent=2) + "\n", encoding="utf-8")

    print(
        f"normalized={len(normalized)} findings={len(aggregate_findings)} errors={len(errors)}",
        file=sys.stderr,
    )
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
