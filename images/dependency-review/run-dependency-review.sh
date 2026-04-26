#!/usr/bin/env bash
# images/dependency-review/run-dependency-review.sh

set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${TARGET_REPO:=/workspace}"
: "${DEPENDENCY_INPUT:=}"
: "${CVE_INDEX_DB:=/data/spt-cve-index.sqlite}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/dependency-review"
RAW_DIR="${RESULTS_DIR}/raw"
NORM_DIR="${RESULTS_DIR}/normalized"
mkdir -p "${RAW_DIR}" "${NORM_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

if [[ -z "${DEPENDENCY_INPUT}" ]]; then
    for candidate in \
        "${TARGET_REPO}/requirements.txt" \
        "${TARGET_REPO}/requirements.lock" \
        "${TARGET_REPO}/sbom.cyclonedx.json" \
        "${TARGET_REPO}/bom.json"; do
        if [[ -f "${candidate}" ]]; then
            DEPENDENCY_INPUT="${candidate}"
            break
        fi
    done
fi

if [[ -z "${DEPENDENCY_INPUT}" || ! -f "${DEPENDENCY_INPUT}" ]]; then
    log_error "Could not determine DEPENDENCY_INPUT from TARGET_REPO=${TARGET_REPO}"
    STATUS=failure
fi

if [[ ! -f "${CVE_INDEX_DB}" ]]; then
    log_error "CVE index database not found: ${CVE_INDEX_DB}"
    STATUS=failure
fi

if [[ "${STATUS}" == "success" ]]; then
    python3 - "${DEPENDENCY_INPUT}" "${CVE_INDEX_DB}" "${RAW_DIR}/enrichment-candidates.json" "${RESULTS_DIR}/tool-result.json" <<'PY' \
        > "${ARTIFACTS_DIR}/logs/dependency-review.log" 2>&1 || STATUS=failure
import datetime as dt
import json
import sqlite3
import sys
from pathlib import Path


def parse_requirements(path: Path) -> list[dict[str, str]]:
    out = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "==" in line:
            name, version = line.split("==", 1)
            out.append({"ecosystem": "PyPI", "name": name.strip(), "version": version.strip()})
        else:
            out.append({"ecosystem": "PyPI", "name": line, "version": ""})
    return out


def parse_cyclonedx(path: Path) -> list[dict[str, str]]:
    data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    out = []
    for component in data.get("components") or []:
        name = str(component.get("name") or "").strip()
        if not name:
            continue
        version = str(component.get("version") or "").strip()
        purl = str(component.get("purl") or "")
        ecosystem = "unknown"
        if purl.startswith("pkg:pypi/"):
            ecosystem = "PyPI"
        elif purl.startswith("pkg:npm/"):
            ecosystem = "npm"
        elif purl.startswith("pkg:maven/"):
            ecosystem = "Maven"
        out.append({"ecosystem": ecosystem, "name": name, "version": version})
    return out


def parse_input(path: Path) -> list[dict[str, str]]:
    if path.suffix.lower() == ".json":
        return parse_cyclonedx(path)
    return parse_requirements(path)


def aliases_for(conn: sqlite3.Connection, cve: str) -> list[str]:
    rows = conn.execute("SELECT alias FROM aliases WHERE cve = ? ORDER BY alias", (cve,)).fetchall()
    return [str(row[0]) for row in rows]


def severity_from_cvss(score: float | None) -> str:
    if score is None:
        return "medium"
    if score >= 9.0:
        return "critical"
    if score >= 7.0:
        return "high"
    if score >= 4.0:
        return "medium"
    return "low"


dependency_input = Path(sys.argv[1])
index_db = Path(sys.argv[2])
enrichment_out = Path(sys.argv[3])
tool_result_out = Path(sys.argv[4])

packages = parse_input(dependency_input)

conn = sqlite3.connect(index_db)
candidates = []
findings = []
try:
    for package in packages:
        rows = conn.execute(
            """
            SELECT
                p.cve,
                p.source,
                p.ranges_json,
                v.summary,
                v.cvss_score,
                v.cvss_vector,
                e.epss,
                e.percentile,
                k.date_added,
                v.source_nvd,
                v.source_osv,
                v.source_ghsa,
                v.source_kev
            FROM packages p
            LEFT JOIN vulnerabilities v ON v.cve = p.cve
            LEFT JOIN epss e ON e.cve = p.cve
            LEFT JOIN kev k ON k.cve = p.cve
            WHERE lower(p.name) = lower(?)
            ORDER BY p.cve
            """,
            (package["name"],),
        ).fetchall()

        for idx, row in enumerate(rows, start=1):
            cve = str(row[0])
            aliases = aliases_for(conn, cve)
            cvss_score = row[4]
            severity = severity_from_cvss(cvss_score)
            candidate = {
                "package": package,
                "cve": cve,
                "aliases": aliases,
                "affected_range": json.loads(row[2]) if row[2] else [],
                "source_records": {
                    "package_source": row[1],
                    "vulnerability_sources": {
                        "nvd": bool(row[9]),
                        "osv": bool(row[10]),
                        "ghsa": bool(row[11]),
                        "kev": bool(row[12]),
                    },
                },
                "cvss": {
                    "score": cvss_score,
                    "vector": row[5],
                },
                "epss": {
                    "score": row[6],
                    "percentile": row[7],
                },
                "kev": {
                    "present": bool(row[8]),
                    "date_added": row[8],
                },
                "summary": row[3],
            }
            candidates.append(candidate)
            findings.append(
                {
                    "id": f"dependency-review-{package['name']}-{idx}",
                    "title": f"{package['name']} potentially affected by {cve}",
                    "severity": severity,
                    "rule_id": "dependency-cve-match",
                    "cve": cve,
                    "message": candidate.get("summary") or f"Offline CVE index match for {package['name']}",
                    "raw": candidate,
                }
            )
finally:
    conn.close()


summary = {"critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0}
for finding in findings:
    summary[finding["severity"]] += 1
summary["total"] = len(findings)

enrichment = {
    "schema_version": "1.0.0",
    "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "dependency_input": str(dependency_input),
    "candidates": candidates,
}
tool_result = {
    "schema_version": "1.0.0",
    "tool": "dependency-review",
    "target": str(dependency_input),
    "summary": summary,
    "findings": findings,
}

enrichment_out.write_text(json.dumps(enrichment, indent=2) + "\n", encoding="utf-8")
tool_result_out.write_text(json.dumps(tool_result, indent=2) + "\n", encoding="utf-8")

print(f"Dependency review candidates: {len(candidates)}")
PY
fi

if [[ "${STATUS}" != "success" ]]; then
    cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "dependency-review",
  "target": "${DEPENDENCY_INPUT:-unknown}",
  "summary": {"total": 0, "critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0},
  "findings": []
}
JSON
fi

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool dependency-review \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "dependency_input=${DEPENDENCY_INPUT}" \
    --extra "cve_index_db=${CVE_INDEX_DB}"

if [[ "${STATUS}" != "success" ]]; then
    exit 1
fi