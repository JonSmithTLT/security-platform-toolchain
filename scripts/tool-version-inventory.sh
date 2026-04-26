#!/usr/bin/env bash
# Probe installed tool versions from built SPT images and check drift.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

REGISTRY="${REGISTRY:-registry.internal/security-platform}"
TAG="${TAG:-latest}"
OUT_DIR="${TOOL_INVENTORY_DIR:-artifacts/tool-inventory}"
JSON_OUT="${OUT_DIR}/installed-tool-versions.json"
MD_OUT="${OUT_DIR}/installed-tool-versions.md"
DRIFT_OUT="${OUT_DIR}/tool-version-drift.md"
MODE="${1:-installed}"

mkdir -p "${OUT_DIR}"

PROBES=(
    "base|python|none|python3 --version"
    "schema-validator|jsonschema|none|python3 -c 'import importlib.metadata as m; print(m.version(\"jsonschema\"))'"
    "semgrep|semgrep|none|semgrep --version"
    "codeql|codeql|CODEQL_VERSION|codeql version"
    "sbom|syft|SYFT_VERSION|syft version"
    "image-scanner|grype|GRYPE_VERSION|grype version"
    "secrets|gitleaks|GITLEAKS_VERSION|gitleaks version"
    "secrets|trufflehog|TRUFFLEHOG_VERSION|trufflehog --version"
    "yara|yara|YARA_VERSION|yara --version"
    "osv-scanner|osv-scanner|OSV_SCANNER_VERSION|osv-scanner --version"
    "gitnexus|gitnexus|GITNEXUS_VERSION|gitnexus --version"
    "ghidra-base|ghidra|GHIDRA_VERSION|/opt/ghidra/support/analyzeHeadless 2>&1 | head -n 2"
    "ghidra-mcp|ghidra-mcp|GHIDRA_MCP_REF|cat /opt/ghidra-mcp/.spt-source-revision"
)

declared_version() {
    local image="$1"
    local variable="$2"
    local dockerfile="images/${image}/Dockerfile"

    if [[ "${variable}" == "none" || ! -f "${dockerfile}" ]]; then
        printf ''
        return
    fi

    awk -F= -v key="${variable}" '$1 == "ARG " key {print $2; exit}' "${dockerfile}"
}

json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

records_file="$(mktemp)"
trap 'rm -f "${records_file}"' EXIT

printf '[' > "${records_file}"
first=1
failures=0
drifts=0

for probe in "${PROBES[@]}"; do
    IFS='|' read -r image component declared_var command <<< "${probe}"
    image_ref="${REGISTRY}/spt-${image}:${TAG}"
    declared="$(declared_version "${image}" "${declared_var}")"

    set +e
    output="$(docker run --rm --network none "${image_ref}" sh -lc "${command}" 2>&1)"
    exit_code=$?
    set -e

    version_match="unknown"
    if [[ -n "${declared}" ]]; then
        if [[ "${output}" == *"${declared}"* ]]; then
            version_match="true"
        else
            version_match="false"
            drifts=$((drifts + 1))
        fi
    fi
    if (( exit_code != 0 )); then
        failures=$((failures + 1))
    fi

    if (( first == 0 )); then
        printf ',' >> "${records_file}"
    fi
    first=0

    python3 - "${records_file}" "${image_ref}" "${component}" "${declared}" "${output}" "${exit_code}" "${version_match}" "${command}" <<'PY'
import json
import sys

path, image, component, declared, output, exit_code, version_match, command = sys.argv[1:9]
record = {
    "image": image,
    "component": component,
    "declared_version": declared or None,
    "installed_version": output.strip(),
    "probe_command": command,
    "probe_exit_code": int(exit_code),
    "version_match": version_match,
}
with open(path, "a", encoding="utf-8") as fh:
    json.dump(record, fh, sort_keys=True)
PY
done
printf ']\n' >> "${records_file}"
cp "${records_file}" "${JSON_OUT}"

python3 - "${JSON_OUT}" "${MD_OUT}" "${DRIFT_OUT}" <<'PY'
import json
import sys

json_path, md_path, drift_path = sys.argv[1:4]
records = json.load(open(json_path, "r", encoding="utf-8"))

def row(record):
    installed = record["installed_version"].replace("\n", "<br>")
    return (
        f"| `{record['image'].split('/')[-1]}` | {record['component']} | "
        f"{record['declared_version'] or ''} | {record['version_match']} | "
        f"{record['probe_exit_code']} | {installed} |\n"
    )

with open(md_path, "w", encoding="utf-8") as fh:
    fh.write("# Installed Tool Versions\n\n")
    fh.write("| Image | Component | Declared | Match | Exit | Installed output |\n")
    fh.write("|---|---|---:|---:|---:|---|\n")
    for record in records:
        fh.write(row(record))

with open(drift_path, "w", encoding="utf-8") as fh:
    fh.write("# Tool Version Drift\n\n")
    drifted = [r for r in records if r["probe_exit_code"] != 0 or r["version_match"] == "false"]
    if not drifted:
        fh.write("No required probe failures or declared-version mismatches found.\n")
    else:
        fh.write("| Image | Component | Declared | Match | Exit | Installed output |\n")
        fh.write("|---|---|---:|---:|---:|---|\n")
        for record in drifted:
            fh.write(row(record))
PY

printf 'Installed tool inventory: %s\n' "${JSON_OUT}"
printf 'Installed tool report:    %s\n' "${MD_OUT}"
printf 'Drift report:             %s\n' "${DRIFT_OUT}"

if [[ "${MODE}" == "drift-check" ]] && (( failures > 0 || drifts > 0 )); then
    printf 'ERROR: %d probe failure(s), %d declared-version drift(s)\n' "${failures}" "${drifts}" >&2
    exit 1
fi
