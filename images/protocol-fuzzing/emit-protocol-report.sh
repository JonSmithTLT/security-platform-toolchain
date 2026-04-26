#!/usr/bin/env bash
set -euo pipefail

: "${ARTIFACTS_DIR:=/artifacts}"
: "${PROTOCOL_NAME:=toy}"
: "${PROTOCOL_TARGET_HOST:=127.0.0.1}"
: "${PROTOCOL_TARGET_PORT:=9001}"
: "${BOOFUZZ_SCRIPT:=/usr/local/lib/spt/toy-boofuzz-campaign.py}"
: "${TARGET_START_CMD:=}"
: "${DURATION_SECONDS:=0}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/protocol-fuzzing"
RAW_DIR="${RESULTS_DIR}/raw"
NORM_DIR="${RESULTS_DIR}/normalized"
EVIDENCE_DIR="${RESULTS_DIR}/evidence/failing-cases"
REPORT_DIR="${RESULTS_DIR}/reports"
mkdir -p "${NORM_DIR}" "${EVIDENCE_DIR}" "${REPORT_DIR}"

python3 - "${RAW_DIR}/boofuzz-results/results.json" "${EVIDENCE_DIR}" "${NORM_DIR}" "${REPORT_DIR}" "${PROTOCOL_NAME}" "${PROTOCOL_TARGET_HOST}" "${PROTOCOL_TARGET_PORT}" "${BOOFUZZ_SCRIPT}" "${TARGET_START_CMD}" "${DURATION_SECONDS}" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

results_path, evidence_dir, norm_dir, report_dir, protocol, host, port, script, start_cmd, duration = sys.argv[1:11]
evidence = Path(evidence_dir)
norm = Path(norm_dir)
report = Path(report_dir)
data = json.loads(Path(results_path).read_text(encoding="utf-8"))
failures = []
for item in data.get("failures", []):
    src = Path(item["path"])
    dest = evidence / src.name
    if src.exists():
        dest.write_bytes(src.read_bytes())
    failures.append({**item, "evidence_path": str(dest), "sha256": hashlib.sha256(dest.read_bytes()).hexdigest() if dest.exists() else ""})

campaign = {
    "schema_version": "1.0.0",
    "protocol": protocol,
    "target_host": host,
    "target_port": int(port),
    "boofuzz_script": script,
    "boofuzz_version": "0.4.2",
    "target_startup_command": start_cmd,
    "duration_seconds": float(duration),
    "test_case_count": int(data.get("case_count", 0)),
    "failure_count": len(failures),
    "failing_case_ids": [f["case_id"] for f in failures],
    "pcap_path": "raw/pcaps/protocol.pcap",
    "replay_command": "replay-boofuzz-case <case-file>",
}
norm.mkdir(parents=True, exist_ok=True)
(norm / "protocol-campaign.json").write_text(json.dumps(campaign, indent=2) + "\n", encoding="utf-8")
(norm / "protocol-failures.json").write_text(json.dumps({"schema_version": "1.0.0", "failures": failures}, indent=2) + "\n", encoding="utf-8")
report.mkdir(parents=True, exist_ok=True)
(report / "protocol-summary.md").write_text(
    f"# Protocol Summary\n\n- Protocol: {protocol}\n- Target: {host}:{port}\n- Test cases: {campaign['test_case_count']}\n- Failures: {len(failures)}\n",
    encoding="utf-8",
)
print(len(failures))
PY
