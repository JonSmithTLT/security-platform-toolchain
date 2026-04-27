#!/usr/bin/env python3
"""Small terminal viewer for SPT release stage ledgers."""

from __future__ import annotations

import argparse
import curses
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from textwrap import shorten


STAGES = [
    "preflight doctor",
    "data fetch",
    "data smoke",
    "image build",
    "verify offline",
    "functional smoke",
    "honggfuzz smoke",
    "image bundle",
    "data bundle",
    "data verify",
    "split bundles",
    "verify split bundles",
    "verify data bundle",
    "write upload manifest",
]

RESUME_POINTS = {
    "data bundle": "make release-smoke RESUME_FROM=data-bundle",
    "split bundles": "make release-smoke RESUME_FROM=split",
    "verify split bundles": "make release-smoke RESUME_FROM=verify",
    "write upload manifest": "make release-smoke RESUME_FROM=upload",
}


@dataclass
class Config:
    ledger: Path
    tag: str
    bundle_dir: Path
    data_bundle_dir: Path
    artifacts_dir: Path


def parse_args() -> argparse.Namespace:
    tag = os.environ.get("TAG", "latest")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--ledger",
        default=os.environ.get(
            "RELEASE_LEDGER", f"artifacts/release-ledger/{tag}/release-stages.jsonl"
        ),
        help="release stage JSONL ledger",
    )
    parser.add_argument("--tag", default=tag)
    parser.add_argument("--bundle-dir", default=os.environ.get("BUNDLE_DIR", "offline-bundles/out"))
    parser.add_argument(
        "--data-bundle-dir",
        default=os.environ.get("DATA_BUNDLE_DIR", "data-bundles/out"),
    )
    parser.add_argument("--artifacts-dir", default="artifacts")
    parser.add_argument(
        "--summary",
        action="store_true",
        help="print a compact summary instead of opening curses",
    )
    return parser.parse_args()


def read_ledger(path: Path) -> list[dict]:
    if not path.exists():
        return []

    records: list[dict] = []
    with path.open("r", encoding="utf-8") as fh:
        for line_no, line in enumerate(fh, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SystemExit(f"{path}:{line_no}: invalid JSON: {exc}") from exc
            records.append(record)
    return records


def latest_by_stage(records: list[dict]) -> dict[str, dict]:
    latest: dict[str, dict] = {}
    for record in records:
        stage = str(record.get("stage", ""))
        if stage:
            latest[stage] = record
    return latest


def artifact_candidates(config: Config) -> list[Path]:
    tag = config.tag
    return [
        config.ledger,
        config.bundle_dir / f"spt-bundle-{tag}.manifest.json",
        config.bundle_dir / f"spt-bundle-{tag}.tar.gz",
        config.bundle_dir / f"spt-bundle-{tag}.parts.sha256",
        config.bundle_dir / f"spt-release-{tag}.upload-assets.txt",
        config.bundle_dir / f"spt-release-{tag}.gh-upload.sh",
        config.data_bundle_dir / f"spt-data-bundle-{tag}.manifest.json",
        config.data_bundle_dir / f"spt-data-bundle-{tag}.tar.gz",
        config.data_bundle_dir / f"spt-data-bundle-{tag}.sha256",
        config.artifacts_dir / "release-summary" / tag / "release-summary.md",
    ]


def status_counts(latest: dict[str, dict]) -> dict[str, int]:
    counts = {"success": 0, "failed": 0, "skipped": 0, "missing": 0}
    for stage in STAGES:
        status = str(latest.get(stage, {}).get("status", "missing"))
        counts[status] = counts.get(status, 0) + 1
    return counts


def print_summary(config: Config, records: list[dict]) -> int:
    latest = latest_by_stage(records)
    counts = status_counts(latest)
    print(f"Release ledger: {config.ledger}")
    print(f"Tag: {config.tag}")
    print(
        "Stages: "
        f"success={counts.get('success', 0)} "
        f"failed={counts.get('failed', 0)} "
        f"skipped={counts.get('skipped', 0)} "
        f"missing={counts.get('missing', 0)}"
    )
    for stage in STAGES:
        record = latest.get(stage, {})
        status = str(record.get("status", "missing"))
        ended = str(record.get("ended_at", "-"))
        note = str(record.get("note", ""))
        suffix = f" ({note})" if note else ""
        print(f"- {stage}: {status} @ {ended}{suffix}")

    existing = [path for path in artifact_candidates(config) if path.exists()]
    if existing:
        print("Artifacts:")
        for path in existing:
            print(f"- {path}")
    return 0


def draw_text(window: curses.window, y: int, x: int, text: str, width: int, attr: int = 0) -> None:
    if y < 0:
        return
    try:
        window.addnstr(y, x, text, max(0, width), attr)
    except curses.error:
        pass


def stage_attr(status: str) -> int:
    if status == "success":
        return curses.color_pair(2)
    if status == "failed":
        return curses.color_pair(1) | curses.A_BOLD
    if status == "skipped":
        return curses.color_pair(3)
    return curses.color_pair(4)


def run_tui(stdscr: curses.window, config: Config, records: list[dict]) -> None:
    curses.curs_set(0)
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_RED, -1)
    curses.init_pair(2, curses.COLOR_GREEN, -1)
    curses.init_pair(3, curses.COLOR_YELLOW, -1)
    curses.init_pair(4, curses.COLOR_CYAN, -1)
    curses.init_pair(5, curses.COLOR_WHITE, curses.COLOR_BLUE)

    latest = latest_by_stage(records)
    selected = 0
    top = 0

    while True:
        height, width = stdscr.getmaxyx()
        stdscr.erase()
        counts = status_counts(latest)
        title = f"SPT release ledger: {config.tag}"
        draw_text(stdscr, 0, 0, title.ljust(width), width, curses.color_pair(5) | curses.A_BOLD)
        summary = (
            f"{config.ledger}  "
            f"ok={counts.get('success', 0)} failed={counts.get('failed', 0)} "
            f"skipped={counts.get('skipped', 0)} missing={counts.get('missing', 0)}"
        )
        draw_text(stdscr, 1, 0, shorten(summary, width=max(10, width - 1)), width - 1)

        list_width = min(42, max(24, width // 2))
        detail_x = list_width + 2
        visible_rows = max(1, height - 5)
        if selected < top:
            top = selected
        if selected >= top + visible_rows:
            top = selected - visible_rows + 1

        for row, stage in enumerate(STAGES[top : top + visible_rows], start=3):
            idx = top + row - 3
            record = latest.get(stage, {})
            status = str(record.get("status", "missing"))
            marker = ">" if idx == selected else " "
            attr = stage_attr(status)
            if idx == selected:
                attr |= curses.A_REVERSE
            line = f"{marker} {status[:7]:7} {stage}"
            draw_text(stdscr, row, 0, line, list_width, attr)

        stage = STAGES[selected]
        record = latest.get(stage, {})
        status = str(record.get("status", "missing"))
        detail_lines = [
            f"Stage: {stage}",
            f"Status: {status}",
            f"Started: {record.get('started_at', '-')}",
            f"Ended: {record.get('ended_at', '-')}",
            f"Command: {record.get('command', '-') or '-'}",
            f"Note: {record.get('note', '-') or '-'}",
            f"Safe resume: {RESUME_POINTS.get(stage, 'not a supported resume point')}",
            "",
            "Artifacts:",
        ]
        existing = [path for path in artifact_candidates(config) if path.exists()]
        detail_lines.extend(str(path) for path in existing)
        if not existing:
            detail_lines.append("- no known release artifacts found yet")

        for offset, line in enumerate(detail_lines):
            draw_text(stdscr, 3 + offset, detail_x, line, max(1, width - detail_x - 1))

        footer = "Up/Down or j/k: select   r: reload   q: quit"
        draw_text(stdscr, height - 1, 0, footer.ljust(width), width, curses.A_REVERSE)
        stdscr.refresh()

        key = stdscr.getch()
        if key in (ord("q"), ord("Q"), 27):
            return
        if key in (curses.KEY_UP, ord("k")):
            selected = max(0, selected - 1)
        elif key in (curses.KEY_DOWN, ord("j")):
            selected = min(len(STAGES) - 1, selected + 1)
        elif key in (ord("r"), ord("R")):
            records = read_ledger(config.ledger)
            latest = latest_by_stage(records)


def main() -> int:
    args = parse_args()
    config = Config(
        ledger=Path(args.ledger),
        tag=args.tag,
        bundle_dir=Path(args.bundle_dir),
        data_bundle_dir=Path(args.data_bundle_dir),
        artifacts_dir=Path(args.artifacts_dir),
    )
    records = read_ledger(config.ledger)
    if args.summary or not sys.stdout.isatty():
        return print_summary(config, records)
    curses.wrapper(run_tui, config, records)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
