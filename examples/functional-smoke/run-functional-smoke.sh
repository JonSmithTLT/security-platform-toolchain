#!/usr/bin/env bash
# Functional smoke test for the offline SPT image bundle.

set -euo pipefail

REGISTRY="${1:-${REGISTRY:-registry.internal/security-platform}}"
TAG="${2:-${TAG:-latest}}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ROOT_DIR}/artifacts/functional-smoke"
FIXTURE_DIR="${OUT_DIR}/fixture"

log() {
    printf '==> %s\n' "$*"
}

image() {
    printf '%s/spt-%s:%s' "${REGISTRY}" "$1" "${TAG}"
}

assert_file() {
    if [[ ! -f "$1" ]]; then
        printf 'missing expected file: %s\n' "$1" >&2
        exit 1
    fi
}

assert_json_number_gt() {
    local file="$1"
    local expr="$2"
    local min="$3"
    docker run --rm --network none \
        -v "${file}:/check.json:ro" \
        "$(image base)" \
        python3 -c "import json; data=json.load(open('/check.json')); value=${expr}; assert value > ${min}, value"
}

finalize_artifacts() {
    local name="$1"
    local dir="$2"
    docker run --rm --network none \
        -e JOB_ID="functional-${name}" \
        -e ARTIFACTS_DIR=/artifacts \
        -v "${dir}:/artifacts" \
        "$(image base)" \
        emit-artifact-manifest --artifacts-dir /artifacts --job-id "functional-${name}"
}

assert_contract() {
    local name="$1"
    local dir="$2"
    assert_file "${dir}/job-report.json"
    assert_file "${dir}/manifest.json"
    if [[ ! -d "${dir}/logs" ]]; then
        printf 'missing expected logs directory: %s/logs\n' "${dir}" >&2
        exit 1
    fi
    if [[ ! -d "${dir}/results" ]]; then
        printf 'missing expected results directory: %s/results\n' "${dir}" >&2
        exit 1
    fi
    docker run --rm --network none \
        -e JOB_ID="functional-${name}-validator" \
        -e ARTIFACTS_DIR=/artifacts \
        -e VALIDATE_TARGET=/artifacts \
        -v "${dir}:/artifacts" \
        "$(image schema-validator)"
    docker run --rm --network none \
        -v "${dir}/results/schema-validator/raw/validation-summary.json:/check.json:ro" \
        "$(image base)" \
        python3 -c "import json; data=json.load(open('/check.json')); assert data['error_count'] == 0, data"
}

rm -rf "${OUT_DIR}"
mkdir -p "${FIXTURE_DIR}"

cat > "${FIXTURE_DIR}/app.py" <<'PY'
import os
import subprocess

password = "hardcoded-password"
cmd = input("cmd: ")
os.system(cmd)
subprocess.call(cmd, shell=True)
PY

cat > "${FIXTURE_DIR}/vuln.c" <<'C'
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    char buf[8];
    if (argc > 1) {
        strcpy(buf, argv[1]);
    }
    printf("%s\n", buf);
    return 0;
}
C

cat > "${FIXTURE_DIR}/requirements.txt" <<'REQ'
requests==2.31.0
REQ

cat > "${FIXTURE_DIR}/secrets.txt" <<'TXT'
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAtestonlytestonlytestonlytestonlytestonlytestonly
-----END RSA PRIVATE KEY-----
TXT

mkdir -p "${OUT_DIR}/rules"
cat > "${OUT_DIR}/rules/demo.yar" <<'YARA'
rule DemoSecretString {
    strings:
        $s = "AKIAIOSFODNN7EXAMPLE"
    condition:
        $s
}
YARA

mkdir -p "${OUT_DIR}/intel"
cat > "${OUT_DIR}/intel/advisory.md" <<'MD'
# Demo Advisory

CWE-78 command injection can occur when shell commands include untrusted input.
Prefer argument arrays and avoid shell=True.
MD

mkdir -p "${OUT_DIR}/eval"
cat > "${OUT_DIR}/eval/cases.jsonl" <<JSONL
{"name":"advisory mentions CWE","file":"${OUT_DIR}/intel/advisory.md","contains":"CWE-78"}
JSONL

log "Semgrep detects fixture findings"
mkdir -p "${OUT_DIR}/semgrep"
docker run --rm --network none \
    -e JOB_ID=functional-semgrep \
    -e ARTIFACTS_DIR=/artifacts \
    -v "${FIXTURE_DIR}:/workspace:ro" \
    -v "${ROOT_DIR}/rules/semgrep:/rules:ro" \
    -v "${OUT_DIR}/semgrep:/artifacts" \
    "$(image semgrep)"
finalize_artifacts semgrep "${OUT_DIR}/semgrep"
assert_contract semgrep "${OUT_DIR}/semgrep"
assert_file "${OUT_DIR}/semgrep/results/semgrep/raw/semgrep.json"
assert_json_number_gt "${OUT_DIR}/semgrep/results/semgrep/raw/semgrep.json" "len(data.get('results', []))" 0

log "Result normalizer converts Semgrep JSON"
docker run --rm --network none \
    -e JOB_ID=functional-normalizers \
    -e ARTIFACTS_DIR=/artifacts \
    -v "${OUT_DIR}/semgrep:/artifacts" \
    "$(image result-normalizers)"
finalize_artifacts normalizers "${OUT_DIR}/semgrep"
assert_file "${OUT_DIR}/semgrep/results/semgrep/tool-result.json"
assert_json_number_gt "${OUT_DIR}/semgrep/results/semgrep/tool-result.json" "len(data.get('findings', []))" 0

log "Schema validator validates normalized artifacts"
docker run --rm --network none \
    -e JOB_ID=functional-validator \
    -e ARTIFACTS_DIR=/artifacts \
    -e VALIDATE_TARGET=/artifacts \
    -v "${OUT_DIR}/semgrep:/artifacts" \
    "$(image schema-validator)"
assert_file "${OUT_DIR}/semgrep/results/schema-validator/raw/validation-summary.json"
docker run --rm --network none \
    -v "${OUT_DIR}/semgrep/results/schema-validator/raw/validation-summary.json:/check.json:ro" \
    "$(image base)" \
    python3 -c "import json; data=json.load(open('/check.json')); assert data['error_count'] == 0, data"

log "SBOM image generates a CycloneDX SBOM"
mkdir -p "${OUT_DIR}/sbom"
docker run --rm --network none \
    -e JOB_ID=functional-sbom \
    -e ARTIFACTS_DIR=/artifacts \
    -v "${FIXTURE_DIR}:/workspace:ro" \
    -v "${OUT_DIR}/sbom:/artifacts" \
    "$(image sbom)"
finalize_artifacts sbom "${OUT_DIR}/sbom"
assert_contract sbom "${OUT_DIR}/sbom"
assert_file "${OUT_DIR}/sbom/sbom/sbom.cyclonedx.json"
assert_json_number_gt "${OUT_DIR}/sbom/sbom/sbom.cyclonedx.json" "len(data.get('components', []))" 0

log "Secrets image executes Gitleaks offline"
mkdir -p "${OUT_DIR}/secrets"
docker run --rm --network none \
    -e JOB_ID=functional-secrets \
    -e ARTIFACTS_DIR=/artifacts \
    -e SECRETS_TOOLS=gitleaks \
    -v "${FIXTURE_DIR}:/workspace:ro" \
    -v "${OUT_DIR}/secrets:/artifacts" \
    "$(image secrets)" || true
finalize_artifacts secrets "${OUT_DIR}/secrets"
assert_contract secrets "${OUT_DIR}/secrets"
assert_file "${OUT_DIR}/secrets/results/secrets/raw/gitleaks.json"
assert_json_number_gt "${OUT_DIR}/secrets/results/secrets/raw/gitleaks.json" "len(data if isinstance(data, list) else [])" 0

log "Image scanner executes Grype offline"
mkdir -p "${OUT_DIR}/image-scanner"
docker run --rm --network none \
    -e JOB_ID=functional-image-scanner \
    -e ARTIFACTS_DIR=/artifacts \
    -e IMAGE_SCAN_TARGET=/workspace \
    -e GRYPE_DB_AUTO_UPDATE=false \
    -e GRYPE_CHECK_FOR_APP_UPDATE=false \
    -v "${FIXTURE_DIR}:/workspace:ro" \
    -v "${OUT_DIR}/image-scanner:/artifacts" \
    "$(image image-scanner)" || true
finalize_artifacts image-scanner "${OUT_DIR}/image-scanner"
assert_contract image-scanner "${OUT_DIR}/image-scanner"
assert_file "${OUT_DIR}/image-scanner/results/image-scanner/raw/grype.json"
if grep -Eiq "failed to fetch latest version|toolbox-data\.anchore\.io|network is unreachable" "${OUT_DIR}/image-scanner/logs/image-scanner.log"; then
    fail "image-scanner attempted a network update/version check"
fi

log "C/C++ analysis executes cppcheck offline"
mkdir -p "${OUT_DIR}/c-cpp-analysis"
docker run --rm --network none \
    -e JOB_ID=functional-c-cpp \
    -e ARTIFACTS_DIR=/artifacts \
    -v "${FIXTURE_DIR}:/workspace:ro" \
    -v "${OUT_DIR}/c-cpp-analysis:/artifacts" \
    "$(image c-cpp-analysis)" || true
finalize_artifacts c-cpp-analysis "${OUT_DIR}/c-cpp-analysis"
assert_contract c-cpp-analysis "${OUT_DIR}/c-cpp-analysis"
assert_file "${OUT_DIR}/c-cpp-analysis/results/c-cpp-analysis/raw/cppcheck.xml"

log "Coverage tools emit coverage artifacts"
mkdir -p "${OUT_DIR}/coverage-tools"
docker run --rm --network none \
    -e JOB_ID=functional-coverage-tools \
    -e ARTIFACTS_DIR=/artifacts \
    -v "${OUT_DIR}/coverage-tools:/artifacts" \
    "$(image coverage-tools)"
finalize_artifacts coverage-tools "${OUT_DIR}/coverage-tools"
assert_contract coverage-tools "${OUT_DIR}/coverage-tools"
assert_file "${OUT_DIR}/coverage-tools/results/coverage-tools/tool-result.json"

log "YARA scans fixture files"
mkdir -p "${OUT_DIR}/yara"
docker run --rm --network none \
    -e JOB_ID=functional-yara \
    -e ARTIFACTS_DIR=/artifacts \
    -v "${FIXTURE_DIR}:/workspace:ro" \
    -v "${OUT_DIR}/rules:/rules:ro" \
    -v "${OUT_DIR}/yara:/artifacts" \
    "$(image yara)"
finalize_artifacts yara "${OUT_DIR}/yara"
assert_contract yara "${OUT_DIR}/yara"
assert_file "${OUT_DIR}/yara/results/yara/tool-result.json"
assert_json_number_gt "${OUT_DIR}/yara/results/yara/tool-result.json" "len(data.get('findings', []))" 0

log "Lightweight RE triage inventories files"
mkdir -p "${OUT_DIR}/re-lightweight"
docker run --rm --network none \
    -e JOB_ID=functional-re-lightweight \
    -e ARTIFACTS_DIR=/artifacts \
    -v "${FIXTURE_DIR}:/workspace:ro" \
    -v "${OUT_DIR}/re-lightweight:/artifacts" \
    "$(image re-lightweight)"
finalize_artifacts re-lightweight "${OUT_DIR}/re-lightweight"
assert_contract re-lightweight "${OUT_DIR}/re-lightweight"
assert_file "${OUT_DIR}/re-lightweight/results/re-lightweight/raw/inventory.jsonl"

log "Intel ingest creates chunks"
mkdir -p "${OUT_DIR}/intel-ingest"
docker run --rm --network none \
    -e JOB_ID=functional-intel-ingest \
    -e ARTIFACTS_DIR=/artifacts \
    -e INTEL_INPUT=/intel \
    -e INTEL_DATASET=demo \
    -e INTEL_VERSION=smoke \
    -v "${OUT_DIR}/intel:/intel:ro" \
    -v "${OUT_DIR}/intel-ingest:/artifacts" \
    "$(image intel-ingest)"
finalize_artifacts intel-ingest "${OUT_DIR}/intel-ingest"
assert_contract intel-ingest "${OUT_DIR}/intel-ingest"
assert_file "${OUT_DIR}/intel-ingest/results/intel-ingest/raw/chunks.jsonl"

log "RAG indexer creates SQLite FTS index"
mkdir -p "${OUT_DIR}/rag-indexer"
docker run --rm --network none \
    -e JOB_ID=functional-rag-indexer \
    -e ARTIFACTS_DIR=/artifacts \
    -e RAG_INPUT=/input/chunks.jsonl \
    -v "${OUT_DIR}/intel-ingest/results/intel-ingest/raw/chunks.jsonl:/input/chunks.jsonl:ro" \
    -v "${OUT_DIR}/rag-indexer:/artifacts" \
    "$(image rag-indexer)"
finalize_artifacts rag-indexer "${OUT_DIR}/rag-indexer"
assert_contract rag-indexer "${OUT_DIR}/rag-indexer"
assert_file "${OUT_DIR}/rag-indexer/results/rag-indexer/raw/rag-index.sqlite"

log "Diff impact inventories changed files"
mkdir -p "${OUT_DIR}/diff-impact"
docker run --rm --network none \
    -e JOB_ID=functional-diff-impact \
    -e ARTIFACTS_DIR=/artifacts \
    -v "${FIXTURE_DIR}:/workspace:ro" \
    -v "${OUT_DIR}/diff-impact:/artifacts" \
    "$(image diff-impact)"
finalize_artifacts diff-impact "${OUT_DIR}/diff-impact"
assert_contract diff-impact "${OUT_DIR}/diff-impact"
assert_file "${OUT_DIR}/diff-impact/results/diff-impact/raw/impact.json"

log "Eval runner executes file-content eval"
mkdir -p "${OUT_DIR}/eval-runner"
docker run --rm --network none \
    -e JOB_ID=functional-eval-runner \
    -e ARTIFACTS_DIR=/artifacts \
    -e EVAL_CASES=/eval/cases.jsonl \
    -v "${OUT_DIR}/eval:/eval:ro" \
    -v "${OUT_DIR}/intel:${OUT_DIR}/intel:ro" \
    -v "${OUT_DIR}/eval-runner:/artifacts" \
    "$(image eval-runner)"
finalize_artifacts eval-runner "${OUT_DIR}/eval-runner"
assert_contract eval-runner "${OUT_DIR}/eval-runner"
assert_file "${OUT_DIR}/eval-runner/results/eval-runner/raw/eval-results.json"

log "Ghidra MCP exposes bundled MCP runtime metadata"
mkdir -p "${OUT_DIR}/ghidra-mcp"
docker run --rm --network none \
    -e JOB_ID=functional-ghidra-mcp \
    -e ARTIFACTS_DIR=/artifacts \
    -e GHIDRA_MCP_MODE=smoke \
    -v "${OUT_DIR}/ghidra-mcp:/artifacts" \
    "$(image ghidra-mcp)"
finalize_artifacts ghidra-mcp "${OUT_DIR}/ghidra-mcp"
assert_contract ghidra-mcp "${OUT_DIR}/ghidra-mcp"
assert_file "${OUT_DIR}/ghidra-mcp/results/ghidra-mcp/raw/environment.json"
assert_file "${OUT_DIR}/ghidra-mcp/results/ghidra-mcp/raw/bridge-help.txt"
assert_file "${OUT_DIR}/ghidra-mcp/results/ghidra-mcp/raw/python-mcp-sdk.txt"

log "Functional smoke test passed"
