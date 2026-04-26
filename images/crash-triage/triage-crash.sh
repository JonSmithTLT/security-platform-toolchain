#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${CRASH_LOG:=/workspace/asan.log}"
: "${CRASH_INPUT:=/workspace/crash}"
: "${CRASH_BINARY:=/workspace/target}"
: "${REPRO_COMMAND:=}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/crash-triage"
RAW_DIR="${RESULTS_DIR}/raw"
NORM_DIR="${RESULTS_DIR}/normalized"
REPORT_DIR="${RESULTS_DIR}/reports"
mkdir -p "${RAW_DIR}/core" "${NORM_DIR}" "${REPORT_DIR}" "${ARTIFACTS_DIR}/logs"

cp "${CRASH_LOG}" "${RAW_DIR}/sanitizer.log"
cp "${CRASH_LOG}" "${RAW_DIR}/crash.log"
[[ -f "${CRASH_INPUT}" ]] && cp "${CRASH_INPUT}" "${RAW_DIR}/crash.input" || true

if grep -q "AddressSanitizer" "${CRASH_LOG}"; then
    parsed="$(parse-asan "${CRASH_LOG}")"
elif grep -q "UndefinedBehaviorSanitizer\|runtime error:" "${CRASH_LOG}"; then
    parsed="$(parse-ubsan "${CRASH_LOG}")"
elif grep -q "ThreadSanitizer" "${CRASH_LOG}"; then
    parsed="$(parse-tsan "${CRASH_LOG}")"
elif grep -q "MemorySanitizer" "${CRASH_LOG}"; then
    parsed="$(parse-msan "${CRASH_LOG}")"
else
    parsed="$(parse-valgrind "${CRASH_LOG}")"
fi
hashes="$(hash-crash "${parsed}")"

python3 - "${parsed}" "${hashes}" "${CRASH_BINARY}" "${CRASH_INPUT}" "${REPRO_COMMAND}" "${NORM_DIR}/crash-triage.json" "${NORM_DIR}/stacktrace.json" "${NORM_DIR}/crash-signature.json" "${REPORT_DIR}/triage.md" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

parsed = json.loads(sys.argv[1])
hashes = json.loads(sys.argv[2])
binary, crash_input, repro = sys.argv[3:6]
triage_out, stack_out, sig_out, report_out = map(Path, sys.argv[6:10])

def digest(path: str) -> str:
    if not path or not os.path.exists(path):
        return ""
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

triage = {
    "schema_version": "1.0.0",
    "crash_type": parsed.get("crash_type", "unknown"),
    "signal": "",
    "sanitizer": parsed.get("sanitizer", "unknown"),
    "binary": binary,
    "binary_sha256": digest(binary),
    "input": crash_input,
    "input_sha256": digest(crash_input),
    "reproduction_command": repro,
    "top_frame": parsed.get("top_frame", ""),
    "frames": parsed.get("frames", []),
    "source_location": parsed.get("source_location", ""),
    "stack_hash": hashes["stack_hash"],
    "dedup_hash": hashes["dedup_hash"],
    "similarity_key": hashes["similarity_key"],
    "confidence": "medium" if parsed.get("top_frame") else "low",
    "limitations": [] if parsed.get("top_frame") else ["No symbolized stack frames found"],
}
triage_out.write_text(json.dumps(triage, indent=2) + "\n", encoding="utf-8")
stack_out.write_text(json.dumps({"schema_version": "1.0.0", "frames": triage["frames"]}, indent=2) + "\n", encoding="utf-8")
sig_out.write_text(json.dumps({"schema_version": "1.0.0", "stack_hash": triage["stack_hash"], "dedup_hash": triage["dedup_hash"], "similarity_key": triage["similarity_key"]}, indent=2) + "\n", encoding="utf-8")
report_out.write_text(f"# Crash Triage\n\n- Type: {triage['crash_type']}\n- Sanitizer: {triage['sanitizer']}\n- Top frame: {triage['top_frame']}\n- Stack hash: {triage['stack_hash']}\n- Dedup hash: {triage['dedup_hash']}\n", encoding="utf-8")
PY
