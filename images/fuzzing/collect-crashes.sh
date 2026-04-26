#!/usr/bin/env bash
set -euo pipefail

ENGINE="${1:?engine required}"
TARGET="${2:?target required}"
RAW_ROOT="${3:?raw root required}"
EVIDENCE_DIR="${4:?evidence dir required}"
OUT_JSON="${5:?output crashes json required}"

mkdir -p "${EVIDENCE_DIR}"

python3 - "${ENGINE}" "${TARGET}" "${RAW_ROOT}" "${EVIDENCE_DIR}" "${OUT_JSON}" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

engine, target, raw_root, evidence_dir, out_json = sys.argv[1:6]
raw = Path(raw_root)
evidence = Path(evidence_dir)
crashes = []

def add(path: Path, kind: str) -> None:
    if not path.is_file():
        return
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    dest = evidence / f"{kind}-{len(crashes) + 1}-{path.name.replace(',', '_')}"
    dest.write_bytes(path.read_bytes())
    replay = f"{target} {dest}" if "@@" not in target else target.replace("@@", str(dest))
    crashes.append({
        "id": f"{engine}-{kind}-{len(crashes) + 1}",
        "path": str(dest),
        "sha256": digest,
        "engine": engine,
        "kind": kind,
        "replay_command": replay,
    })

if engine == "afl":
    for candidate in sorted(raw.glob("afl-out/default/crashes/id:*")):
        if "README" not in candidate.name:
            add(candidate, "crash")
    for candidate in sorted(raw.glob("afl-out/default/hangs/id:*")):
        add(candidate, "hang")
elif engine == "libfuzzer":
    for candidate in sorted(raw.glob("libfuzzer-out/crash-*")):
        add(candidate, "crash")
    for candidate in sorted(raw.glob("libfuzzer-out/timeout-*")):
        add(candidate, "hang")
elif engine == "honggfuzz":
    for candidate in sorted(raw.glob("honggfuzz-out/*")):
        add(candidate, "crash")

Path(out_json).parent.mkdir(parents=True, exist_ok=True)
Path(out_json).write_text(json.dumps({"schema_version": "1.0.0", "crashes": crashes}, indent=2) + "\n", encoding="utf-8")
print(len(crashes))
PY
