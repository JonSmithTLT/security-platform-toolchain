#!/usr/bin/env python3
"""Generate soft candidate correlations from normalized tool findings."""

from __future__ import annotations

import argparse
import datetime as dt
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class Observation:
    tool: str
    finding_id: str
    rule_id: str
    file: str
    line_start: int | None
    line_end: int | None
    cve: str
    cwe: set[str]


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def load_tool_results(results_dir: Path) -> dict[str, list[Observation]]:
    loaded: dict[str, list[Observation]] = {}
    for tool_result in sorted(results_dir.glob("*/tool-result.json")):
        tool = tool_result.parent.name
        data = json.loads(tool_result.read_text(encoding="utf-8", errors="replace"))
        observations: list[Observation] = []
        for finding in data.get("findings") or []:
            if not isinstance(finding, dict):
                continue
            location = finding.get("location") or {}
            cwe_values = finding.get("cwe") or []
            observations.append(
                Observation(
                    tool=tool,
                    finding_id=str(finding.get("id") or ""),
                    rule_id=str(finding.get("rule_id") or ""),
                    file=str(location.get("file") or ""),
                    line_start=location.get("line_start"),
                    line_end=location.get("line_end"),
                    cve=str(finding.get("cve") or ""),
                    cwe={str(item) for item in cwe_values if str(item)},
                )
            )
        loaded[tool] = observations
    return loaded


def signal_same_rule_same_location(a: Observation, b: Observation) -> dict[str, Any] | None:
    if a.rule_id and a.rule_id == b.rule_id and a.file and a.file == b.file:
        return {"type": "same_rule_same_location", "weight": 0.8, "value": f"{a.rule_id}:{a.file}"}
    return None


def signal_same_dependency_cve(a: Observation, b: Observation) -> dict[str, Any] | None:
    if a.cve and a.cve == b.cve:
        return {"type": "same_dependency_cve", "weight": 0.9, "value": a.cve}
    return None


def signal_shared_cwe(a: Observation, b: Observation) -> dict[str, Any] | None:
    overlap = sorted(a.cwe & b.cwe)
    if overlap:
        return {"type": "shared_cwe_pattern", "weight": 0.6, "value": ",".join(overlap)}
    return None


def signal_location_overlap(a: Observation, b: Observation) -> dict[str, Any] | None:
    if not a.file or a.file != b.file:
        return None
    if a.line_start is None or b.line_start is None:
        return None
    a_end = a.line_end or a.line_start
    b_end = b.line_end or b.line_start
    if max(a.line_start, b.line_start) <= min(a_end, b_end):
        return {
            "type": "source_location_overlap",
            "weight": 0.5,
            "value": f"{a.file}:{a.line_start}-{a_end}~{b.line_start}-{b_end}",
        }
    return None


def relationship_type(signals: list[dict[str, Any]]) -> str:
    kinds = {signal["type"] for signal in signals}
    if "same_dependency_cve" in kinds:
        return "same_dependency_cve"
    if "same_rule_same_location" in kinds:
        return "same_rule_same_location"
    if "shared_cwe_pattern" in kinds:
        return "shared_cwe_pattern"
    return "possibly_related"


def recommended_action(confidence: float) -> str:
    if confidence >= 0.8:
        return "review"
    if confidence >= 0.5:
        return "attach_as_context"
    return "ignore_low_confidence"


def correlations_for_tool(tool: str, all_observations: dict[str, list[Observation]]) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    source_observations = all_observations.get(tool, [])
    for source in source_observations:
        for observations in all_observations.values():
            for target in observations:
                if source.tool == target.tool and source.finding_id == target.finding_id:
                    continue
                signals = [
                    signal
                    for signal in (
                        signal_same_dependency_cve(source, target),
                        signal_same_rule_same_location(source, target),
                        signal_shared_cwe(source, target),
                        signal_location_overlap(source, target),
                    )
                    if signal is not None
                ]
                if not signals:
                    continue

                confidence = min(1.0, round(sum(float(signal["weight"]) for signal in signals), 2))
                output.append(
                    {
                        "candidate_relationship_type": relationship_type(signals),
                        "confidence": confidence,
                        "signals": signals,
                        "source_observation_refs": [
                            {"tool": source.tool, "finding_id": source.finding_id}
                        ],
                        "target_observation_refs": [
                            {"tool": target.tool, "finding_id": target.finding_id}
                        ],
                        "recommended_action": recommended_action(confidence),
                    }
                )
    return output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", default="artifacts/results")
    parser.add_argument("--out-dir", default="artifacts/results")
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    out_dir = Path(args.out_dir)
    if not results_dir.exists():
        raise SystemExit(f"results directory not found: {results_dir}")

    all_observations = load_tool_results(results_dir)
    written = 0
    for tool in sorted(all_observations):
        relationships = correlations_for_tool(tool, all_observations)
        payload = {
            "schema_version": "1.0.0",
            "generated_at": utc_now(),
            "tool": tool,
            "relationships": relationships,
        }
        out_path = out_dir / tool / "normalized" / "candidate-correlations.json"
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        written += 1

    print(f"Candidate-correlation artifacts written: {written}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())