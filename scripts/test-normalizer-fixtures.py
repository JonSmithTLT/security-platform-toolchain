#!/usr/bin/env python3
"""Run golden fixture contract tests for result normalizers."""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
NORMALIZER = ROOT / "images" / "result-normalizers" / "result-normalizers.py"


def load_normalizer_module() -> Any:
    spec = importlib.util.spec_from_file_location("spt_result_normalizers", NORMALIZER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load normalizer module from {NORMALIZER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def assert_subset(expected: Any, actual: Any, path: str = "$") -> None:
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            raise AssertionError(f"{path}: expected object, got {type(actual).__name__}")
        for key, expected_value in expected.items():
            if key not in actual:
                raise AssertionError(f"{path}.{key}: missing key")
            assert_subset(expected_value, actual[key], f"{path}.{key}")
        return

    if isinstance(expected, list):
        if not isinstance(actual, list):
            raise AssertionError(f"{path}: expected list, got {type(actual).__name__}")
        if len(expected) != len(actual):
            raise AssertionError(f"{path}: expected {len(expected)} items, got {len(actual)}")
        for index, expected_value in enumerate(expected):
            assert_subset(expected_value, actual[index], f"{path}[{index}]")
        return

    if actual != expected:
        raise AssertionError(f"{path}: expected {expected!r}, got {actual!r}")


def raw_file_for(fixture_dir: Path) -> Path:
    raw_dir = fixture_dir / "raw"
    files = sorted(path for path in raw_dir.iterdir() if path.is_file())
    if len(files) != 1:
        raise AssertionError(f"{fixture_dir}: expected exactly one raw fixture file, found {len(files)}")
    return files[0]


def run_fixture(fixture_dir: Path) -> None:
    expected_path = fixture_dir / "expected.json"
    raw_path = raw_file_for(fixture_dir)
    normalizer_module = load_normalizer_module()
    fmt = normalizer_module.detect(raw_path, "auto")
    normalizer = normalizer_module.NORMALIZERS[fmt]
    _tool, actual = normalizer(raw_path)
    expected = load_json(expected_path)
    assert_subset(expected, actual)
    sarif = normalizer_module.tool_result_to_sarif(actual)
    if sarif.get("version") != "2.1.0":
        raise AssertionError(f"{fixture_dir}: SARIF export did not declare version 2.1.0")
    sarif_results = sarif.get("runs", [{}])[0].get("results", [])
    if len(sarif_results) != len(actual.get("findings", [])):
        raise AssertionError(f"{fixture_dir}: SARIF result count did not match finding count")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--fixtures-dir",
        default=str(ROOT / "examples" / "normalizer-fixtures"),
        help="Directory containing <tool>/raw and expected.json fixtures.",
    )
    args = parser.parse_args()

    fixtures_dir = Path(args.fixtures_dir)
    failures: list[str] = []
    for fixture_dir in sorted(path for path in fixtures_dir.iterdir() if path.is_dir()):
        try:
            run_fixture(fixture_dir)
            print(f"PASS {fixture_dir.name}")
        except Exception as exc:  # noqa: BLE001 - test runner reports all fixture failures.
            failures.append(f"{fixture_dir.name}: {exc}")
            print(f"FAIL {fixture_dir.name}: {exc}", file=sys.stderr)

    if failures:
        print("\nNormalizer fixture failures:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(f"\nNormalizer fixture tests passed: {fixtures_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
