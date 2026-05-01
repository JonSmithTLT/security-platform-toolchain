#!/usr/bin/env bash
# Functional smoke test for the offline SPT image bundle.

set -euo pipefail
# Ensure artifact directories are world-writable so the spt user (UID 1001)
# inside containers can write to bind-mounted paths created by the host user.
# On NTFS/WSL this is automatic; on native Linux ext4 the default umask (022)
# produces 755 directories that block container writes.
umask 0000

REGISTRY="${1:-${REGISTRY:-registry.internal/security-platform}}"
TAG="${2:-${TAG:-latest}}"
DATA_DIR="${3:-${DATA_DIR:-data-bundles/sources}}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ "${DATA_DIR}" != /* ]]; then
    DATA_DIR="${ROOT_DIR}/${DATA_DIR}"
fi
DATA_DIR="$(cd "${DATA_DIR}" && pwd)"
OUT_DIR="${ROOT_DIR}/artifacts/functional-smoke"
FIXTURE_DIR="${OUT_DIR}/fixture"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

log() {
    printf '==> %s\n' "$*"
}

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

image() {
    printf '%s/spt-%s:%s' "${REGISTRY}" "$1" "${TAG}"
}

repair_artifact_ownership() {
    [[ -e "${OUT_DIR}" ]] || return 0
    docker run --rm --network none --user 0 \
        -v "${OUT_DIR}:/target" \
        "$(image base)" \
        sh -c "chown -R ${HOST_UID}:${HOST_GID} /target" >/dev/null 2>&1 || true
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

write_coverage_inventory() {
    mkdir -p "${OUT_DIR}"
    cat > "${OUT_DIR}/functional-smoke-coverage.txt" <<'TXT'
covered:
  base
  python-wheelhouse-py311
  python-runtime
  schema-validator
  result-normalizers
  c-cpp-analysis
  coverage-tools
  harness-builder
  fuzzing
  protocol-fuzzing
  crash-triage
  replay-runner
  sbom
  secrets
  image-scanner
  re-lightweight
  yara
  intel-ingest
  rag-indexer
  diff-impact
  dependency-review
  ghidra-base
  ghidra-mcp
  eval-runner
  gitnexus
  semgrep
  corpus-tools
  symbolic

not-covered-in-functional-smoke:
  codeql
  ghidra-exporter
  osv-scanner

notes:
  ghidra-base is exercised indirectly through ghidra-mcp.
  codeql and ghidra-exporter are intentionally heavier than the default functional smoke.
  osv-scanner needs a valid offline OSV database cache for a meaningful functional pass.
TXT
}

trap repair_artifact_ownership EXIT
repair_artifact_ownership
rm -rf "${OUT_DIR}"
mkdir -p "${FIXTURE_DIR}"
write_coverage_inventory

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

cat > "${FIXTURE_DIR}/afl_harness.c" <<'C'
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 2) return 0;
    FILE *fp = fopen(argv[1], "rb");
    if (!fp) return 1;
    char buf[8] = {0};
    size_t n = fread(buf, 1, sizeof(buf), fp);
    fclose(fp);
    if (n >= 4 && buf[0] == 'C' && buf[1] == 'R' && buf[2] == 'S' && buf[3] == 'H') abort();
    return 0;
}
C

cat > "${FIXTURE_DIR}/libfuzzer_harness.c" <<'C'
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size >= 4 && data[0] == 'C' && data[1] == 'R' && data[2] == 'S' && data[3] == 'H') abort();
    return 0;
}
C

cat > "${FIXTURE_DIR}/asan.log" <<'LOG'
==1==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x602000000014 at pc 0x000000401234 bp 0x7fff00000000 sp 0x7fff00000000
READ of size 1 at 0x602000000014 thread T0
    #0 0x401234 in parse_packet /workspace/parser.c:42:9
    #1 0x401345 in LLVMFuzzerTestOneInput /workspace/harness.c:12:5
    #2 0x401456 in main /src/compiler-rt/lib/fuzzer/FuzzerMain.cpp:20:10
SUMMARY: AddressSanitizer: heap-buffer-overflow /workspace/parser.c:42:9 in parse_packet
LOG

cat > "${FIXTURE_DIR}/requirements.txt" <<'REQ'
requests==2.31.0
REQ

cat > "${FIXTURE_DIR}/replay-target.sh" <<'SH'
#!/usr/bin/env bash
if grep -q CRSH "$1"; then
    kill -ABRT $$
fi
exit 0
SH
chmod +x "${FIXTURE_DIR}/replay-target.sh"

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

log "Python runtime imports core offline utilities"
docker run --rm --network none \
    "$(image python-runtime)" \
    python3 -c "import click, jsonschema, requests, rich, typer, yaml; print('python-runtime imports OK')"

log "Python wheelhouse carrier exposes py311 locks and wheels"
docker run --rm --network none \
    "$(image python-wheelhouse-py311)" \
    sh -c 'test -f /requirements/py311/core-python.lock && test -d /wheelhouse/py311/core-python && find /wheelhouse/py311/core-python -name "*.whl" | grep -q .'

mkdir -p "${OUT_DIR}/dependency-db"
python3 - "${OUT_DIR}/dependency-db/spt-cve-index.sqlite" <<'PY'
import sqlite3
import sys

db = sys.argv[1]
conn = sqlite3.connect(db)
conn.executescript(
    """
    CREATE TABLE packages (name TEXT, cve TEXT, source TEXT, ranges_json TEXT);
    CREATE TABLE vulnerabilities (
        cve TEXT PRIMARY KEY,
        summary TEXT,
        cvss_score REAL,
        cvss_vector TEXT,
        source_nvd INTEGER,
        source_osv INTEGER,
        source_ghsa INTEGER,
        source_kev INTEGER
    );
    CREATE TABLE epss (cve TEXT PRIMARY KEY, epss REAL, percentile REAL);
    CREATE TABLE kev (cve TEXT PRIMARY KEY, date_added TEXT);
    CREATE TABLE aliases (cve TEXT, alias TEXT);
    INSERT INTO packages VALUES ('requests', 'CVE-2099-0001', 'fixture', '[]');
    INSERT INTO vulnerabilities VALUES (
        'CVE-2099-0001',
        'Functional smoke fixture dependency match',
        7.5,
        'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N',
        1,
        0,
        0,
        0
    );
    INSERT INTO epss VALUES ('CVE-2099-0001', 0.42, 0.9);
    """
)
conn.commit()
conn.close()
PY

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

log "Harness builder generates/builds/smokes AFL harness"
mkdir -p "${OUT_DIR}/harness-builder-afl"
docker run --rm --network none \
    -e JOB_ID=functional-harness-builder-afl \
    -e ARTIFACTS_DIR=/artifacts \
    -e HARNESS_ENGINE=afl \
    -e HARNESS_NAME=afl_smoke \
    -v "${OUT_DIR}/harness-builder-afl:/artifacts" \
    "$(image harness-builder)"
finalize_artifacts harness-builder-afl "${OUT_DIR}/harness-builder-afl"
assert_contract harness-builder-afl "${OUT_DIR}/harness-builder-afl"
assert_file "${OUT_DIR}/harness-builder-afl/results/harness-builder/normalized/harness-manifest.json"
assert_file "${OUT_DIR}/harness-builder-afl/results/harness-builder/raw/generated/harness.c"
assert_file "${OUT_DIR}/harness-builder-afl/results/harness-builder/raw/build/afl_smoke"

log "Harness builder generates/builds/smokes libFuzzer harness"
mkdir -p "${OUT_DIR}/harness-builder-libfuzzer"
docker run --rm --network none \
    -e JOB_ID=functional-harness-builder-libfuzzer \
    -e ARTIFACTS_DIR=/artifacts \
    -e HARNESS_ENGINE=libfuzzer \
    -e HARNESS_NAME=libfuzzer_smoke \
    -v "${OUT_DIR}/harness-builder-libfuzzer:/artifacts" \
    "$(image harness-builder)"
finalize_artifacts harness-builder-libfuzzer "${OUT_DIR}/harness-builder-libfuzzer"
assert_contract harness-builder-libfuzzer "${OUT_DIR}/harness-builder-libfuzzer"
assert_file "${OUT_DIR}/harness-builder-libfuzzer/results/harness-builder/normalized/harness-manifest.json"
assert_file "${OUT_DIR}/harness-builder-libfuzzer/results/harness-builder/raw/generated/harness.c"
assert_file "${OUT_DIR}/harness-builder-libfuzzer/results/harness-builder/raw/build/libfuzzer_smoke"

log "Fuzzing runs AFL campaign offline"
mkdir -p "${OUT_DIR}/fuzz-afl/corpus" "${OUT_DIR}/fuzz-afl/artifacts"
printf 'A' > "${OUT_DIR}/fuzz-afl/corpus/seed"
docker run --rm --network none \
    -v "${FIXTURE_DIR}:/src:ro" \
    -v "${OUT_DIR}/fuzz-afl/corpus:/corpus" \
    -v "${OUT_DIR}/fuzz-afl/artifacts:/artifacts" \
    "$(image fuzzing)" \
    bash -lc "afl-clang-fast -g -O1 -o /tmp/afl_harness /src/afl_harness.c && FUZZ_ENGINE=afl FUZZ_TARGET=/tmp/afl_harness FUZZ_CORPUS=/corpus FUZZ_TIMEOUT=2 ARTIFACTS_DIR=/artifacts run-fuzzing"
finalize_artifacts fuzz-afl "${OUT_DIR}/fuzz-afl/artifacts"
assert_contract fuzz-afl "${OUT_DIR}/fuzz-afl/artifacts"
assert_file "${OUT_DIR}/fuzz-afl/artifacts/results/fuzzing/normalized/fuzz-campaign.json"
assert_file "${OUT_DIR}/fuzz-afl/artifacts/results/fuzzing/normalized/crashes.json"

log "Fuzzing runs libFuzzer campaign offline"
mkdir -p "${OUT_DIR}/fuzz-libfuzzer/corpus" "${OUT_DIR}/fuzz-libfuzzer/artifacts"
printf 'A' > "${OUT_DIR}/fuzz-libfuzzer/corpus/seed"
docker run --rm --network none \
    -v "${FIXTURE_DIR}:/src:ro" \
    -v "${OUT_DIR}/fuzz-libfuzzer/corpus:/corpus" \
    -v "${OUT_DIR}/fuzz-libfuzzer/artifacts:/artifacts" \
    "$(image fuzzing)" \
    bash -lc "clang -g -O1 -fsanitize=fuzzer,address,undefined -o /tmp/libfuzzer_harness /src/libfuzzer_harness.c && FUZZ_ENGINE=libfuzzer FUZZ_TARGET=/tmp/libfuzzer_harness FUZZ_CORPUS=/corpus FUZZ_TIMEOUT=2 ARTIFACTS_DIR=/artifacts run-fuzzing"
finalize_artifacts fuzz-libfuzzer "${OUT_DIR}/fuzz-libfuzzer/artifacts"
assert_contract fuzz-libfuzzer "${OUT_DIR}/fuzz-libfuzzer/artifacts"
assert_file "${OUT_DIR}/fuzz-libfuzzer/artifacts/results/fuzzing/normalized/fuzz-campaign.json"
assert_file "${OUT_DIR}/fuzz-libfuzzer/artifacts/results/fuzzing/normalized/crashes.json"

log "Protocol fuzzing captures toy failing case offline"
mkdir -p "${OUT_DIR}/protocol-fuzzing"
docker run --rm --network none \
    -e JOB_ID=functional-protocol-fuzzing \
    -e ARTIFACTS_DIR=/artifacts \
    -v "${OUT_DIR}/protocol-fuzzing:/artifacts" \
    "$(image protocol-fuzzing)"
finalize_artifacts protocol-fuzzing "${OUT_DIR}/protocol-fuzzing"
assert_contract protocol-fuzzing "${OUT_DIR}/protocol-fuzzing"
assert_file "${OUT_DIR}/protocol-fuzzing/results/protocol-fuzzing/normalized/protocol-campaign.json"
assert_json_number_gt "${OUT_DIR}/protocol-fuzzing/results/protocol-fuzzing/normalized/protocol-campaign.json" "data.get('failure_count', 0)" 0

log "Crash triage parses ASAN report offline"
mkdir -p "${OUT_DIR}/crash-triage"
printf 'CRSH' > "${OUT_DIR}/crash.input"
docker run --rm --network none \
    -e JOB_ID=functional-crash-triage \
    -e ARTIFACTS_DIR=/artifacts \
    -e CRASH_LOG=/workspace/asan.log \
    -e CRASH_INPUT=/workspace/crash.input \
    -v "${FIXTURE_DIR}/asan.log:/workspace/asan.log:ro" \
    -v "${OUT_DIR}/crash.input:/workspace/crash.input:ro" \
    -v "${OUT_DIR}/crash-triage:/artifacts" \
    "$(image crash-triage)"
finalize_artifacts crash-triage "${OUT_DIR}/crash-triage"
assert_contract crash-triage "${OUT_DIR}/crash-triage"
assert_file "${OUT_DIR}/crash-triage/results/crash-triage/normalized/crash-triage.json"

log "Replay runner reproduces a crash input offline"
mkdir -p "${OUT_DIR}/replay-runner/crashes" "${OUT_DIR}/replay-runner/artifacts"
printf 'CRSH' > "${OUT_DIR}/replay-runner/crashes/crash-1"
docker run --rm --network none \
    -e JOB_ID=functional-replay-runner \
    -e ARTIFACTS_DIR=/artifacts \
    -e REPLAY_TARGET=/workspace/replay-target.sh \
    -e CRASH_DIR=/crashes \
    -e REPLAY_TIMEOUT=5 \
    -v "${FIXTURE_DIR}:/workspace:ro" \
    -v "${OUT_DIR}/replay-runner/crashes:/crashes:ro" \
    -v "${OUT_DIR}/replay-runner/artifacts:/artifacts" \
    "$(image replay-runner)" || true
finalize_artifacts replay-runner "${OUT_DIR}/replay-runner/artifacts"
assert_contract replay-runner "${OUT_DIR}/replay-runner/artifacts"
assert_file "${OUT_DIR}/replay-runner/artifacts/results/replay-runner/normalized/replay-result.json"
assert_json_number_gt "${OUT_DIR}/replay-runner/artifacts/results/replay-runner/normalized/replay-result.json" "len(data.get('results', []))" 0

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

log "Dependency review queries a local CVE index offline"
mkdir -p "${OUT_DIR}/dependency-review"
docker run --rm --network none \
    -e JOB_ID=functional-dependency-review \
    -e ARTIFACTS_DIR=/artifacts \
    -e TARGET_REPO=/workspace \
    -e DEPENDENCY_INPUT=/workspace/requirements.txt \
    -e CVE_INDEX_DB=/data/spt-cve-index.sqlite \
    -v "${FIXTURE_DIR}:/workspace:ro" \
    -v "${OUT_DIR}/dependency-db/spt-cve-index.sqlite:/data/spt-cve-index.sqlite:ro" \
    -v "${OUT_DIR}/dependency-review:/artifacts" \
    "$(image dependency-review)"
finalize_artifacts dependency-review "${OUT_DIR}/dependency-review"
assert_contract dependency-review "${OUT_DIR}/dependency-review"
assert_file "${OUT_DIR}/dependency-review/results/dependency-review/raw/enrichment-candidates.json"
assert_json_number_gt "${OUT_DIR}/dependency-review/results/dependency-review/tool-result.json" "len(data.get('findings', []))" 0

log "Corpus tools deduplicate a tiny corpus offline"
mkdir -p "${OUT_DIR}/corpus/input" "${OUT_DIR}/corpus/artifacts"
printf 'seed-a' > "${OUT_DIR}/corpus/input/a"
printf 'seed-a' > "${OUT_DIR}/corpus/input/a-copy"
printf 'seed-b' > "${OUT_DIR}/corpus/input/b"
docker run --rm --network none \
    -e JOB_ID=functional-corpus-tools \
    -e ARTIFACTS_DIR=/artifacts \
    -e CORPUS_MODE=deduplicate \
    -e CORPUS_DIR=/corpus-in \
    -e CORPUS_OUT=/artifacts/corpus-out \
    -v "${OUT_DIR}/corpus/input:/corpus-in:ro" \
    -v "${OUT_DIR}/corpus/artifacts:/artifacts" \
    "$(image corpus-tools)"
finalize_artifacts corpus-tools "${OUT_DIR}/corpus/artifacts"
assert_contract corpus-tools "${OUT_DIR}/corpus/artifacts"
assert_file "${OUT_DIR}/corpus/artifacts/results/corpus-tools/normalized/corpus-summary.json"
assert_json_number_gt "${OUT_DIR}/corpus/artifacts/results/corpus-tools/normalized/corpus-summary.json" "data.get('output_file_count', 0)" 0

log "GitNexus indexes a real git repo with offline Ladybug extensions"
compgen -G "${DATA_DIR}/ladybug-extensions/*/*/fts/libfts.lbug_extension" >/dev/null || fail "missing LadybugDB fts extension under ${DATA_DIR}/ladybug-extensions"
compgen -G "${DATA_DIR}/ladybug-extensions/*/*/vector/libvector.lbug_extension" >/dev/null || fail "missing LadybugDB vector extension under ${DATA_DIR}/ladybug-extensions"
mkdir -p "${OUT_DIR}/gitnexus"
docker run --rm --network none \
    -e JOB_ID=functional-gitnexus \
    -e ARTIFACTS_DIR=/artifacts \
    -e HOME=/tmp/spt-home \
    -e GITNEXUS_MODE=analyze \
    -e GITNEXUS_TARGET=/tmp/gitnexus-fixture-repo \
    -e GITNEXUS_FIXTURE_REPO=1 \
    -e GITNEXUS_REQUIRE_LADYBUG_EXTENSIONS=1 \
    -e GITNEXUS_LADYBUG_EXTENSIONS_DIR=/data/ladybug-extensions \
    -e GITNEXUS_OFFLINE=1 \
    -e SPT_OFFLINE=1 \
    -v "${DATA_DIR}/ladybug-extensions:/data/ladybug-extensions:ro" \
    -v "${OUT_DIR}/gitnexus:/artifacts" \
    "$(image gitnexus)"
finalize_artifacts gitnexus "${OUT_DIR}/gitnexus"
assert_file "${OUT_DIR}/gitnexus/results/gitnexus/raw/gitnexus-provenance.json"
assert_file "${OUT_DIR}/gitnexus/results/gitnexus/raw/ladybug-extension-staging.txt"
assert_file "${OUT_DIR}/gitnexus/results/gitnexus/raw/gitnexus-index-files.txt"
if [[ ! -s "${OUT_DIR}/gitnexus/results/gitnexus/raw/gitnexus-index-files.txt" ]]; then
    fail "GitNexus index artifact list is empty"
fi
assert_file "${OUT_DIR}/gitnexus/results/gitnexus/normalized/gitnexus-summary.json"
if grep -Eiq "Failed to download extension|extension\.ladybugdb\.com|VECTOR extension load failed|FTS extension load failed" "${OUT_DIR}/gitnexus/logs/gitnexus.log"; then
    fail "GitNexus attempted external Ladybug extension fetch during functional smoke"
fi
if grep -Eiq "passing --skip-git|skip.git" "${OUT_DIR}/gitnexus/logs/gitnexus.log"; then
    fail "GitNexus did not exercise git metadata path during functional smoke"
fi
docker run --rm --network none \
    -v "${OUT_DIR}/gitnexus/job-report.json:/check.json:ro" \
    "$(image base)" \
    python3 -c "import json; data=json.load(open('/check.json')); assert data['tool'] == 'gitnexus', data; assert data['gitnexus_version'], data; assert data['source_ref'] and data['source_ref'] != 'unknown', data; assert 'source_commit' in data, data; assert data['source_repo'] == 'https://github.com/abhigyanpatwari/GitNexus', data"
assert_contract gitnexus "${OUT_DIR}/gitnexus"
docker run --rm --network none \
    -v "${OUT_DIR}/gitnexus/results/gitnexus/normalized/gitnexus-summary.json:/check.json:ro" \
    "$(image base)" \
    python3 -c "import json; data=json.load(open('/check.json')); assert data['exit_code'] == 0, data; assert data['source_repo'] == 'https://github.com/abhigyanpatwari/GitNexus', data; assert data['source_ref'] and data['source_ref'] != 'unknown', data; assert 'source_commit' in data, data; assert data['cli_entrypoint'], data; assert data['source_present'] is True, data; assert data['dependencies_present'] is True, data; assert data['ladybug_extensions_available'] is True, data; assert data['ladybug_extensions_required'] == 1, data; assert data['ladybug_classification'] == 'extension_load_success', data; assert data['index_present'] is True, data"
docker run --rm --network none \
    -v "${OUT_DIR}/gitnexus/results/gitnexus/raw/gitnexus-provenance.json:/check.json:ro" \
    "$(image base)" \
    python3 -c "import json; data=json.load(open('/check.json')); assert data['source_repo'] == 'https://github.com/abhigyanpatwari/GitNexus', data; assert data['source_ref'] and data['source_ref'] != 'unknown', data; assert 'source_commit' in data, data; assert data['package_name'] == 'gitnexus', data; assert data['package_version'], data; assert data['cli_entrypoint_exists'] is True, data; assert data['source_present'] is True, data; assert data['dependencies_present'] is True, data"

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

log "Symbolic image runs angr against a tiny binary"
mkdir -p "${OUT_DIR}/symbolic"
docker run --rm --network none \
    -e JOB_ID=functional-symbolic \
    -e ARTIFACTS_DIR=/artifacts \
    -v "${FIXTURE_DIR}:/src:ro" \
    -v "${OUT_DIR}/symbolic:/artifacts" \
    "$(image symbolic)" \
    bash -lc "gcc -g -O0 -o /tmp/symbolic-target /src/vuln.c && TARGET_BINARY=/tmp/symbolic-target SYMBOLIC_TIMEOUT=20 ARTIFACTS_DIR=/artifacts run-symbolic"
finalize_artifacts symbolic "${OUT_DIR}/symbolic"
assert_contract symbolic "${OUT_DIR}/symbolic"
assert_file "${OUT_DIR}/symbolic/results/symbolic/raw/angr-results.json"
assert_json_number_gt "${OUT_DIR}/symbolic/results/symbolic/raw/angr-results.json" "data.get('states_active', 0) + data.get('states_deadended', 0) + data.get('states_errored', 0) + data.get('states_unconstrained', 0)" 0
assert_file "${OUT_DIR}/symbolic/results/symbolic/normalized/symbolic-summary.json"

log "Functional smoke test passed"
