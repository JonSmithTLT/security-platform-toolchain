#!/usr/bin/env python3
"""Generate descriptive MCP/tool catalog from wrappers and repository metadata."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_REFERENCES = [
    "schemas/job-report.schema.json",
    "schemas/artifact-manifest.schema.json",
    "schemas/tool-result.schema.json",
]


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def detect_wrapper(image_dir: Path) -> Path | None:
    run_wrappers = sorted(image_dir.glob("run-*.sh"))
    if run_wrappers:
        return run_wrappers[0]
    shell_files = sorted(path for path in image_dir.glob("*.sh") if path.name != "entrypoint.sh")
    return shell_files[0] if shell_files else None


def parse_env_defaults(wrapper: Path) -> dict[str, str]:
    pattern = re.compile(r":\s*\"\$\{([A-Z0-9_]+):=([^}]*)\}\"")
    defaults: dict[str, str] = {}
    for line in wrapper.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.search(line)
        if match:
            defaults[match.group(1)] = match.group(2)
    return defaults


def mount_hints_from_env(defaults: dict[str, str]) -> list[str]:
    hints: set[str] = set()
    for value in defaults.values():
        if value.startswith("/") and any(token in value for token in ("/workspace", "/artifacts", "/data", "/rules", "/queries")):
            hints.add(value)
    return sorted(hints)


def load_mcp_examples(path: Path) -> dict[str, dict[str, Any]]:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    by_id: dict[str, dict[str, Any]] = {}
    for tool in data.get("tools") or []:
        if isinstance(tool, dict) and tool.get("id"):
            by_id[str(tool["id"])] = tool
    return by_id


def build_tool_entry(
    image_name: str,
    wrapper: Path | None,
    defaults: dict[str, str],
    mcp_examples: dict[str, dict[str, Any]],
    registry: str,
    tag: str,
) -> dict[str, Any]:
    tool_id = f"spt-{image_name}"
    entry = {
        "id": tool_id,
        "image": f"{registry}/{tool_id}:{tag}",
        "wrapper": wrapper.relative_to(ROOT).as_posix() if wrapper else None,
        "environment_defaults": defaults,
        "mount_path_hints": mount_hints_from_env(defaults),
        "schemas": SCHEMA_REFERENCES,
        "example_invocation": (
            f"docker run --rm --network none -v <workspace>:/workspace:ro -v <artifacts>:/artifacts {registry}/{tool_id}:{tag}"
        ),
    }

    if tool_id in mcp_examples:
        entry["mcp_example"] = mcp_examples[tool_id]
    return entry


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--out-dir", default="artifacts/tool-catalog")
    args = parser.parse_args()

    out_dir = ROOT / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    mcp_examples = load_mcp_examples(ROOT / "examples" / "mcp" / "toolchain.mcp.json")
    tools: list[dict[str, Any]] = []

    for image_dir in sorted(path for path in (ROOT / "images").iterdir() if path.is_dir()):
        wrapper = detect_wrapper(image_dir)
        defaults = parse_env_defaults(wrapper) if wrapper else {}
        tools.append(
            build_tool_entry(
                image_name=image_dir.name,
                wrapper=wrapper,
                defaults=defaults,
                mcp_examples=mcp_examples,
                registry=args.registry,
                tag=args.tag,
            )
        )

    catalog = {
        "schema_version": "1.0.0",
        "generated_at": utc_now(),
        "registry": args.registry,
        "tag": args.tag,
        "description": "Descriptive MCP/tool catalog generated from wrappers and repo metadata.",
        "notes": [
            "This catalog is descriptive and non-authoritative for vulnerability semantics.",
            "Canonical finding identity and deduplication remain importer/platform concerns.",
        ],
        "tools": tools,
    }

    json_out = out_dir / "tool-catalog.json"
    md_out = out_dir / "tool-catalog.md"
    json_out.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")

    with md_out.open("w", encoding="utf-8") as fh:
        fh.write("# Generated Tool Catalog\n\n")
        fh.write(f"- Registry: {args.registry}\n")
        fh.write(f"- Tag: {args.tag}\n")
        fh.write(f"- Tools: {len(tools)}\n\n")
        fh.write("| Tool | Wrapper | Env defaults | Mount hints |\n")
        fh.write("|---|---|---:|---|\n")
        for tool in tools:
            wrapper = tool["wrapper"] or ""
            mount_hints = ", ".join(tool["mount_path_hints"])
            fh.write(
                f"| {tool['id']} | {wrapper} | {len(tool['environment_defaults'])} | {mount_hints} |\n"
            )

    print(f"Tool catalog JSON: {json_out}")
    print(f"Tool catalog report: {md_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())