#!/usr/bin/env python3
"""Run offline smoke (optional) and audit logs for observable egress attempts."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("network-fetch", re.compile(r"https?://", re.I)),
    ("network-dial", re.compile(r"dial\s+tcp|connect\(|connection\s+refused", re.I)),
    ("dns-lookup", re.compile(r"lookup\s+.+\s+no\s+such\s+host|temporary\s+failure\s+in\s+name\s+resolution", re.I)),
    ("offline-egress", re.compile(r"failed\s+to\s+download\s+extension|extension\.ladybugdb\.com", re.I)),
    ("timeout", re.compile(r"i/o timeout|timed\s+out|tls\s+handshake\s+timeout", re.I)),
    ("network-unreachable", re.compile(r"network\s+is\s+unreachable|enetunreach", re.I)),
]


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def run_functional_smoke(registry: str, tag: str, data_dir: str) -> None:
    cmd = [
        "bash",
        "examples/functional-smoke/run-functional-smoke.sh",
        registry,
        tag,
        data_dir,
    ]
    subprocess.run(cmd, cwd=ROOT, check=True)


def find_logs(logs_root: Path) -> list[Path]:
    if not logs_root.exists():
        return []
    return sorted(path for path in logs_root.rglob("*.log") if path.is_file())


def classify_confidence(kind: str, line: str) -> str:
    lowered = line.lower()
    if kind in {"network-dial", "dns-lookup", "network-unreachable", "offline-egress"}:
        return "high"
    if kind == "timeout":
        return "medium"
    if kind == "network-fetch" and any(token in lowered for token in ("failed", "error", "download", "fetch", "connect")):
        return "medium"
    return "low"


def scan_log(path: Path, root: Path) -> list[dict[str, object]]:
    findings: list[dict[str, object]] = []
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    rel = path.relative_to(root).as_posix()
    for idx, line in enumerate(lines, start=1):
        for kind, pattern in PATTERNS:
            if pattern.search(line):
                findings.append(
                    {
                        "kind": kind,
                        "confidence": classify_confidence(kind, line),
                        "file": rel,
                        "line": idx,
                        "text": line.strip()[:500],
                    }
                )
                break
    return findings


def summary_by_confidence(findings: list[dict[str, object]]) -> dict[str, int]:
    out = {"high": 0, "medium": 0, "low": 0}
    for finding in findings:
        confidence = str(finding.get("confidence", "low"))
        out[confidence] = out.get(confidence, 0) + 1
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--logs-root", default="artifacts/functional-smoke")
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--run-functional-smoke", action="store_true")
    parser.add_argument("--allow-findings", action="store_true")
    args = parser.parse_args()

    logs_root = ROOT / args.logs_root
    out_dir = ROOT / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.run_functional_smoke:
        run_functional_smoke(args.registry, args.tag, args.data_dir)

    log_files = find_logs(logs_root)
    findings: list[dict[str, object]] = []
    for log_file in log_files:
        findings.extend(scan_log(log_file, ROOT))

    summary = summary_by_confidence(findings)
    report = {
        "schema_version": "1.0.0",
        "generated_at": utc_now(),
        "tag": args.tag,
        "registry": args.registry,
        "logs_root": str(logs_root),
        "log_files_scanned": len(log_files),
        "findings": findings,
        "summary": {
            "total": len(findings),
            "high": summary.get("high", 0),
            "medium": summary.get("medium", 0),
            "low": summary.get("low", 0),
        },
        "note": "Observable evidence only. No packet capture or syscall interception is performed.",
    }

    json_path = out_dir / "offline-egress-audit.json"
    md_path = out_dir / "offline-egress-audit.md"
    json_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    with md_path.open("w", encoding="utf-8") as fh:
        fh.write("# Offline Egress Audit\n\n")
        fh.write(f"- Tag: {args.tag}\n")
        fh.write(f"- Registry: {args.registry}\n")
        fh.write(f"- Logs scanned: {len(log_files)}\n")
        fh.write(f"- Findings: {len(findings)} (high={summary.get('high', 0)}, medium={summary.get('medium', 0)}, low={summary.get('low', 0)})\n\n")
        fh.write("| Confidence | Kind | File | Line | Snippet |\n")
        fh.write("|---|---|---|---:|---|\n")
        for finding in findings:
            snippet = str(finding["text"]).replace("|", "\\|")
            fh.write(
                f"| {finding['confidence']} | {finding['kind']} | {finding['file']} | {finding['line']} | {snippet} |\n"
            )

    print(f"Offline egress audit JSON: {json_path}")
    print(f"Offline egress audit report: {md_path}")
    print(f"Offline egress findings: {len(findings)}")

    high_confidence = summary.get("high", 0)
    if high_confidence > 0 and not args.allow_findings:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())