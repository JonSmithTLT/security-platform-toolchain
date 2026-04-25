#!/usr/bin/env python3
"""
images/symbolic/angr-explore.py
Minimal angr symbolic exploration script.

Usage:
    angr-explore.py <binary> <output.json>

Performs a depth-first CFG exploration and records paths that reach
error states (e.g. unconstrained PC, explicit error sinks).
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <binary> <output.json>", file=sys.stderr)
        return 1

    binary = sys.argv[1]
    output_path = Path(sys.argv[2])

    try:
        import angr  # type: ignore
    except ImportError:
        print("[ERROR] angr is not installed", file=sys.stderr)
        return 1

    print(f"[INFO] Loading {binary}", file=sys.stderr)
    project = angr.Project(binary, auto_load_libs=False)

    print("[INFO] Starting symbolic exploration", file=sys.stderr)
    start = time.monotonic()

    state = project.factory.entry_state()
    simgr = project.factory.simulation_manager(state)

    findings: list[dict] = []

    try:
        simgr.run(n=200)  # bound exploration to 200 steps
    except Exception as exc:  # noqa: BLE001
        print(f"[WARN] Exploration stopped early: {exc}", file=sys.stderr)

    elapsed = time.monotonic() - start

    # Collect unconstrained (potential arbitrary-PC) states
    for state in simgr.unconstrained:
        findings.append({
            "type": "unconstrained_pc",
            "description": "Symbolic instruction pointer — potential control-flow hijack",
            "severity": "high",
            "pc": hex(state.solver.eval(state.regs.ip)),
        })

    # Collect errored states
    for state in simgr.errored:
        findings.append({
            "type": "error_state",
            "description": str(state.error),
            "severity": "medium",
        })

    result = {
        "schema_version": "1.0.0",
        "tool": "angr",
        "target": binary,
        "elapsed_seconds": round(elapsed, 2),
        "states_active": len(simgr.active),
        "states_deadended": len(simgr.deadended),
        "states_errored": len(simgr.errored),
        "states_unconstrained": len(simgr.unconstrained),
        "findings": findings,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)
        fh.write("\n")

    print(f"[INFO] Results written to {output_path}", file=sys.stderr)
    print(f"[INFO] Findings: {len(findings)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
