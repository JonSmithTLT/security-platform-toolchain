#!/usr/bin/env python3
"""Run simple offline file-content evaluation cases."""

from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cases", required=True)
    parser.add_argument("--results-out", required=True)
    args = parser.parse_args()

    cases_path = Path(args.cases)
    results_out = Path(args.results_out)
    results_out.parent.mkdir(parents=True, exist_ok=True)

    cases = []
    if cases_path.exists():
        for line in cases_path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                cases.append(json.loads(line))

    results = []
    for case in cases:
        path = Path(case.get("file", ""))
        expected = str(case.get("contains", ""))
        text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
        passed = bool(expected) and expected in text
        results.append({"name": case.get("name", str(path)), "passed": passed, "file": str(path)})

    pass_count = sum(1 for result in results if result["passed"])
    fail_count = len(results) - pass_count
    payload = {
        "schema_version": "1.0.0",
        "generated_at": utc_now(),
        "case_count": len(results),
        "pass_count": pass_count,
        "fail_count": fail_count,
        "results": results,
    }
    results_out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return 1 if fail_count else 0


if __name__ == "__main__":
    raise SystemExit(main())
