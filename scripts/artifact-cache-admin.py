#!/usr/bin/env python3
"""Inspect, verify, and prune the SPT content-addressed artifact cache."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import shutil
import sys
from pathlib import Path


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def parse_cached_at(value: str) -> dt.datetime | None:
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def human_size(size: int) -> str:
    value = float(size)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if value < 1024 or unit == "TiB":
            return f"{value:.1f} {unit}" if unit != "B" else f"{size} B"
        value /= 1024
    return f"{size} B"


def entry_size(path: Path) -> int:
    total = 0
    for child in path.rglob("*"):
        if child.is_file():
            total += child.stat().st_size
    return total


def load_manifest(entry: Path) -> dict[str, str]:
    manifest = entry / ".spt-manifest.json"
    if not manifest.exists():
        return {"key": entry.name, "label": "(missing manifest)", "cached_at": ""}
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"key": entry.name, "label": "(invalid manifest)", "cached_at": ""}
    return {
        "key": str(data.get("key") or entry.name),
        "label": str(data.get("label") or ""),
        "cached_at": str(data.get("cached_at") or ""),
        "source_dir": str(data.get("source_dir") or ""),
    }


def iter_entries(cache_root: Path) -> list[Path]:
    if not cache_root.exists():
        return []
    return sorted(path for path in cache_root.iterdir() if path.is_dir())


def verify_entry(entry: Path) -> tuple[bool, list[str]]:
    sums = entry / ".spt-checksums"
    if not sums.exists():
        return False, ["missing .spt-checksums"]

    errors: list[str] = []
    for line in sums.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip():
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            errors.append(f"invalid checksum line: {line}")
            continue
        expected, rel = parts
        target = entry / rel.strip().lstrip("./")
        if not target.exists():
            errors.append(f"missing file: {rel}")
            continue
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        if digest != expected:
            errors.append(f"checksum mismatch: {rel}")
    return not errors, errors


def cmd_list(args: argparse.Namespace) -> int:
    rows = []
    for entry in iter_entries(args.cache_root):
        manifest = load_manifest(entry)
        cached_at = parse_cached_at(manifest.get("cached_at", ""))
        age_days = ""
        if cached_at is not None:
            age_days = str(max(0, (utc_now() - cached_at).days))
        rows.append(
            {
                "key": manifest["key"],
                "label": manifest.get("label", ""),
                "cached_at": manifest.get("cached_at", ""),
                "age_days": age_days,
                "size": entry_size(entry),
            }
        )

    if args.json:
        print(json.dumps(rows, indent=2, sort_keys=True))
        return 0

    print(f"Cache root: {args.cache_root}")
    print(f"{'Key':64}  {'Label':30}  {'Age':>5}  {'Size':>10}")
    print(f"{'-' * 64}  {'-' * 30}  {'-' * 5}  {'-' * 10}")
    for row in rows:
        print(
            f"{row['key'][:64]:64}  {row['label'][:30]:30}  "
            f"{row['age_days']:>5}  {human_size(row['size']):>10}"
        )
    return 0


def cmd_size(args: argparse.Namespace) -> int:
    by_label: dict[str, int] = {}
    total = 0
    for entry in iter_entries(args.cache_root):
        manifest = load_manifest(entry)
        label = manifest.get("label", "") or "(unknown)"
        label_type = label.split(":", 1)[0]
        size = entry_size(entry)
        total += size
        by_label[label_type] = by_label.get(label_type, 0) + size

    if args.json:
        print(json.dumps({"total": total, "by_type": by_label}, indent=2, sort_keys=True))
        return 0

    print(f"Cache root: {args.cache_root}")
    print(f"Total: {human_size(total)}")
    for label_type, size in sorted(by_label.items()):
        print(f"- {label_type}: {human_size(size)}")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    failed = 0
    checked = 0
    for entry in iter_entries(args.cache_root):
        checked += 1
        ok, errors = verify_entry(entry)
        if ok:
            print(f"OK   {entry.name}")
        else:
            failed += 1
            print(f"FAIL {entry.name}")
            for error in errors:
                print(f"  - {error}")
    print(f"Verified entries: {checked}; failed: {failed}")
    return 1 if failed else 0


def cmd_prune(args: argparse.Namespace) -> int:
    if args.confirm != "yes":
        print("ERROR: prune deletes cache entries. Re-run with CONFIRM=yes.", file=sys.stderr)
        return 2

    cutoff = utc_now() - dt.timedelta(days=args.older_than_days)
    removed = 0
    reclaimed = 0
    for entry in iter_entries(args.cache_root):
        manifest = load_manifest(entry)
        cached_at = parse_cached_at(manifest.get("cached_at", ""))
        if cached_at is None or cached_at >= cutoff:
            continue
        size = entry_size(entry)
        shutil.rmtree(entry)
        removed += 1
        reclaimed += size
        print(f"Removed {entry.name} ({human_size(size)})")

    print(f"Pruned entries: {removed}; reclaimed: {human_size(reclaimed)}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--cache-root",
        type=Path,
        default=Path.home() / ".spt-artifact-cache",
        help="Artifact cache root",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    list_parser = sub.add_parser("list", help="List cache entries")
    list_parser.add_argument("--json", action="store_true", help="Emit JSON")
    list_parser.set_defaults(func=cmd_list)

    size_parser = sub.add_parser("size", help="Show cache size totals")
    size_parser.add_argument("--json", action="store_true", help="Emit JSON")
    size_parser.set_defaults(func=cmd_size)

    verify_parser = sub.add_parser("verify", help="Verify all cached checksums")
    verify_parser.set_defaults(func=cmd_verify)

    prune_parser = sub.add_parser("prune", help="Prune old cache entries")
    prune_parser.add_argument("--older-than-days", type=int, default=30)
    prune_parser.add_argument("--confirm", default="")
    prune_parser.set_defaults(func=cmd_prune)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    args.cache_root = args.cache_root.expanduser()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
