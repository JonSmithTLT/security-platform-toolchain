#!/usr/bin/env bash
# images/gitnexus/gitnexus.sh
# Runs the real GitNexus CLI/MCP code intelligence tool.

set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${ARTIFACTS_DIR:=/artifacts}"
: "${GITNEXUS_MODE:=version}"   # version | analyze | status | list | setup | mcp | serve
: "${GITNEXUS_TARGET:=/workspace}"
: "${GITNEXUS_ANALYZE_ARGS:=}"
: "${GITNEXUS_EXTRA_ARGS:=}"
: "${GITNEXUS_SOURCE_REPO:=https://github.com/abhigyanpatwari/GitNexus}"
: "${GITNEXUS_SOURCE_REF:=unknown}"
: "${GITNEXUS_SOURCE_COMMIT:=unknown}"
: "${GITNEXUS_PACKAGE_NAME:=gitnexus}"
: "${GITNEXUS_PACKAGE_PATH:=/usr/local/lib/node_modules/gitnexus}"
: "${GITNEXUS_LADYBUG_EXTENSIONS_DIR:=/data/ladybug-extensions}"
: "${GITNEXUS_REQUIRE_LADYBUG_EXTENSIONS:=0}"
: "${GITNEXUS_FIXTURE_REPO:=0}"
: "${GITNEXUS_OFFLINE:=}"
: "${SPT_OFFLINE:=}"
export HOME="${HOME:-/tmp/spt-home}" GITNEXUS_OFFLINE SPT_OFFLINE

RESULTS_DIR="${ARTIFACTS_DIR}/results/gitnexus"
RAW_DIR="${RESULTS_DIR}/raw"
NORM_DIR="${RESULTS_DIR}/normalized"
REPORT_DIR="${RESULTS_DIR}/reports"
mkdir -p "${RAW_DIR}" "${NORM_DIR}" "${REPORT_DIR}" "${ARTIFACTS_DIR}/logs"
mkdir -p "${HOME}"

if ! command -v gitnexus >/dev/null 2>&1; then
    log_error "gitnexus CLI is not installed in this image"
    exit 127
fi

run_and_capture() {
    local logfile="$1"
    shift
    set +e
    "$@" 2>&1 | tee "${logfile}"
    local exit_code=${PIPESTATUS[0]}
    set -e
    return "${exit_code}"
}

START_TIME=$(date +%s)
STATUS=success
EXIT_CODE=0
LADYBUG_EXTENSIONS_AVAILABLE=false
LADYBUG_CLASSIFICATION=not_checked

prepare_ladybug_extensions() {
    if [[ ! -d "${GITNEXUS_LADYBUG_EXTENSIONS_DIR}" ]]; then
        if [[ "${GITNEXUS_REQUIRE_LADYBUG_EXTENSIONS}" == "1" ]]; then
            log_error "GITNEXUS_REQUIRE_LADYBUG_EXTENSIONS=1 but ${GITNEXUS_LADYBUG_EXTENSIONS_DIR} is missing"
            return 1
        fi
        return 0
    fi
    if ! find "${GITNEXUS_LADYBUG_EXTENSIONS_DIR}" -type f -name '*.lbug_extension' | grep -q .; then
        if [[ "${GITNEXUS_REQUIRE_LADYBUG_EXTENSIONS}" == "1" ]]; then
            log_error "GITNEXUS_REQUIRE_LADYBUG_EXTENSIONS=1 but no .lbug_extension files were found under ${GITNEXUS_LADYBUG_EXTENSIONS_DIR}"
            return 1
        fi
        return 0
    fi
    LADYBUG_EXTENSIONS_AVAILABLE=true
    {
        printf 'whoami=%s\n' "$(whoami)"
        printf 'HOME=%s\n' "${HOME}"
        printf 'source_dir=%s\n' "${GITNEXUS_LADYBUG_EXTENSIONS_DIR}"
    } > "${RAW_DIR}/ladybug-extension-staging.txt"
    for cache_dir in \
        "${HOME}/.ladybug/extensions" \
        "${HOME}/.ladybug/extension" \
        "${HOME}/.lbug/extensions" \
        "${HOME}/.lbug/extension" \
        "${HOME}/.kuzu/extensions" \
        "${HOME}/.kuzu/extension"; do
        mkdir -p "${cache_dir}"
        cp -R "${GITNEXUS_LADYBUG_EXTENSIONS_DIR}/." "${cache_dir}/" 2>/dev/null || true
        while IFS= read -r ext_file; do
            ext_name="$(basename "${ext_file}")"
            ext_name="${ext_name#lib}"
            ext_name="${ext_name%.lbug_extension}"
            mkdir -p "${cache_dir}/${ext_name}"
            cp "${ext_file}" "${cache_dir}/${ext_name}/$(basename "${ext_file}")" 2>/dev/null || true
            cp "${ext_file}" "${cache_dir}/$(basename "${ext_file}")" 2>/dev/null || true
        done < <(find "${GITNEXUS_LADYBUG_EXTENSIONS_DIR}" -type f -name '*.lbug_extension' | sort)
    done
    {
        printf '\n# staged files\n'
        find "${HOME}" -maxdepth 6 -type f -name '*.lbug_extension' -print | sort
    } >> "${RAW_DIR}/ladybug-extension-staging.txt"
    log_info "Staged LadybugDB extensions from ${GITNEXUS_LADYBUG_EXTENSIONS_DIR}"
}

classify_ladybug_result() {
    local log_file="${ARTIFACTS_DIR}/logs/gitnexus.log"
    if [[ "${GITNEXUS_REQUIRE_LADYBUG_EXTENSIONS}" != "1" ]]; then
        LADYBUG_CLASSIFICATION=not_required
        return 0
    fi
    if [[ "${LADYBUG_EXTENSIONS_AVAILABLE}" != "true" ]]; then
        LADYBUG_CLASSIFICATION=extensions_missing
        return 0
    fi
    if grep -Eiq "Failed to download extension|extension\.ladybugdb\.com" "${log_file}" 2>/dev/null; then
        LADYBUG_CLASSIFICATION=network_fetch_attempted
        return 0
    fi
    if grep -Eiq "symbol|ABI|undefined symbol|incompatible|wrong ELF|cannot open shared object|invalid.*extension" "${log_file}" 2>/dev/null; then
        LADYBUG_CLASSIFICATION=extension_abi_mismatch
        return 0
    fi
    if grep -Eiq "VECTOR extension load failed|FTS extension load failed|extension load failed" "${log_file}" 2>/dev/null; then
        LADYBUG_CLASSIFICATION=extensions_present_not_used
        return 0
    fi
    LADYBUG_CLASSIFICATION=extension_load_success
}

case "${GITNEXUS_MODE}" in
    version)
        run_and_capture "${ARTIFACTS_DIR}/logs/gitnexus.log" gitnexus --version || EXIT_CODE=$?
        ;;
    analyze)
        if prepare_ladybug_extensions; then
            if [[ "${GITNEXUS_FIXTURE_REPO}" == "1" ]]; then
                rm -rf "${GITNEXUS_TARGET}"
                mkdir -p "${GITNEXUS_TARGET}"
                cd "${GITNEXUS_TARGET}"
                git init >> "${ARTIFACTS_DIR}/logs/gitnexus.log" 2>&1
                git config user.email "smoke@example.local" >> "${ARTIFACTS_DIR}/logs/gitnexus.log" 2>&1
                git config user.name "SPT Smoke" >> "${ARTIFACTS_DIR}/logs/gitnexus.log" 2>&1
                cat > main.c <<'EOF'
#include <stdio.h>

int add(int a, int b) {
    return a + b;
}

int main(void) {
    printf("%d\n", add(1, 2));
    return 0;
}
EOF
                cat > README.md <<'EOF'
# GitNexus Smoke Fixture

Tiny repository used to validate offline GitNexus indexing.
EOF
                git add . >> "${ARTIFACTS_DIR}/logs/gitnexus.log" 2>&1
                git commit -m "initial smoke fixture" >> "${ARTIFACTS_DIR}/logs/gitnexus.log" 2>&1
                log_info "Fixture git repo created at ${GITNEXUS_TARGET}"
            fi
            _SPT_SKIP_GIT=""
            if [[ ! -d "${GITNEXUS_TARGET}/.git" && ! -f "${GITNEXUS_TARGET}/.git" ]]; then
                log_warn "${GITNEXUS_TARGET} is not a git repo; passing --skip-git to GitNexus"
                _SPT_SKIP_GIT="--skip-git"
            fi
            cd "${GITNEXUS_TARGET}"
            # shellcheck disable=SC2086
            run_and_capture "${ARTIFACTS_DIR}/logs/gitnexus.log" gitnexus analyze . ${_SPT_SKIP_GIT} ${GITNEXUS_ANALYZE_ARGS} ${GITNEXUS_EXTRA_ARGS} || EXIT_CODE=$?
        else
            EXIT_CODE=$?
        fi
        ;;
    status)
        # shellcheck disable=SC2086
        run_and_capture "${ARTIFACTS_DIR}/logs/gitnexus.log" gitnexus status ${GITNEXUS_EXTRA_ARGS} || EXIT_CODE=$?
        ;;
    list)
        # shellcheck disable=SC2086
        run_and_capture "${ARTIFACTS_DIR}/logs/gitnexus.log" gitnexus list ${GITNEXUS_EXTRA_ARGS} || EXIT_CODE=$?
        ;;
    setup)
        # shellcheck disable=SC2086
        run_and_capture "${ARTIFACTS_DIR}/logs/gitnexus.log" gitnexus setup ${GITNEXUS_EXTRA_ARGS} || EXIT_CODE=$?
        ;;
    mcp)
        cd "${GITNEXUS_TARGET}"
        # shellcheck disable=SC2086
        exec gitnexus mcp ${GITNEXUS_EXTRA_ARGS}
        ;;
    serve)
        cd "${GITNEXUS_TARGET}"
        # shellcheck disable=SC2086
        exec gitnexus serve ${GITNEXUS_EXTRA_ARGS}
        ;;
    *)
        log_error "Unknown GITNEXUS_MODE=${GITNEXUS_MODE}; expected version|analyze|status|list|setup|mcp|serve"
        EXIT_CODE=2
        ;;
esac

classify_ladybug_result
if [[ "${GITNEXUS_REQUIRE_LADYBUG_EXTENSIONS}" == "1" ]]; then
    if grep -Eiq "Failed to download extension|extension\.ladybugdb\.com|VECTOR extension load failed|FTS extension load failed" "${ARTIFACTS_DIR}/logs/gitnexus.log" 2>/dev/null; then
        log_error "GitNexus attempted external LadybugDB extension loading even though offline extensions were required"
        EXIT_CODE=1
    fi
fi

if [[ "${EXIT_CODE}" -ne 0 ]]; then
    STATUS=failure
fi

VERSION="$(gitnexus --version 2>/dev/null || true)"
CLI_PATH="$(command -v gitnexus)"
INDEX_PRESENT=false
if [[ -d "${GITNEXUS_TARGET}/.gitnexus" ]]; then
    INDEX_PRESENT=true
    rm -rf "${RAW_DIR}/gitnexus-index"
    mkdir -p "${RAW_DIR}/gitnexus-index"
    cp -R "${GITNEXUS_TARGET}/.gitnexus/." "${RAW_DIR}/gitnexus-index/" 2>/dev/null || true
    find "${RAW_DIR}/gitnexus-index" -type f -print | sort > "${RAW_DIR}/gitnexus-index-files.txt" || true
fi
SOURCE_PRESENT=false
if [[ -f "${GITNEXUS_PACKAGE_PATH}/package.json" ]]; then
    SOURCE_PRESENT=true
fi
DEPENDENCIES_PRESENT=false
if [[ -d "${GITNEXUS_PACKAGE_PATH}/node_modules" ]]; then
    DEPENDENCIES_PRESENT=true
fi

python3 - "${RAW_DIR}/gitnexus-provenance.json" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

out = Path(sys.argv[1])
pkg_path = Path(os.environ.get("GITNEXUS_PACKAGE_PATH", "/usr/local/lib/node_modules/gitnexus"))
pkg_json = pkg_path / "package.json"
package = {}
if pkg_json.exists():
    package = json.loads(pkg_json.read_text(encoding="utf-8"))

entrypoint = subprocess.run(
    ["bash", "-lc", "command -v gitnexus"],
    check=False,
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    text=True,
).stdout.strip()

provenance = {
    "schema_version": "1.0.0",
    "source_repo": os.environ.get("GITNEXUS_SOURCE_REPO", ""),
    "source_ref": os.environ.get("GITNEXUS_SOURCE_REF", ""),
    "source_commit": os.environ.get("GITNEXUS_SOURCE_COMMIT", ""),
    "package_name": os.environ.get("GITNEXUS_PACKAGE_NAME", "gitnexus"),
    "package_path": str(pkg_path),
    "package_version": package.get("version", ""),
    "package_repository": package.get("repository", ""),
    "package_license": package.get("license", ""),
    "source_present": pkg_json.exists(),
    "dependencies_present": (pkg_path / "node_modules").is_dir(),
    "ladybug_extensions_dir": os.environ.get("GITNEXUS_LADYBUG_EXTENSIONS_DIR", ""),
    "cli_entrypoint": entrypoint,
    "cli_entrypoint_exists": bool(entrypoint),
}
out.write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
PY

cat > "${NORM_DIR}/gitnexus-summary.json" <<JSON
{
  "schema_version": "1.0.0",
  "mode": "${GITNEXUS_MODE}",
  "target": "${GITNEXUS_TARGET}",
  "version": "${VERSION}",
  "source_repo": "${GITNEXUS_SOURCE_REPO}",
  "source_ref": "${GITNEXUS_SOURCE_REF}",
  "source_commit": "${GITNEXUS_SOURCE_COMMIT}",
  "package_name": "${GITNEXUS_PACKAGE_NAME}",
  "package_path": "${GITNEXUS_PACKAGE_PATH}",
  "cli_entrypoint": "${CLI_PATH}",
  "source_present": ${SOURCE_PRESENT},
  "dependencies_present": ${DEPENDENCIES_PRESENT},
  "ladybug_extensions_available": ${LADYBUG_EXTENSIONS_AVAILABLE},
  "ladybug_extensions_required": ${GITNEXUS_REQUIRE_LADYBUG_EXTENSIONS},
  "ladybug_classification": "${LADYBUG_CLASSIFICATION}",
  "index_present": ${INDEX_PRESENT},
  "exit_code": ${EXIT_CODE}
}
JSON

cat > "${REPORT_DIR}/gitnexus-summary.md" <<EOF
# GitNexus Summary

- Mode: ${GITNEXUS_MODE}
- Target: ${GITNEXUS_TARGET}
- Version: ${VERSION}
- Source repo: ${GITNEXUS_SOURCE_REPO}
- Source ref: ${GITNEXUS_SOURCE_REF}
- Source commit: ${GITNEXUS_SOURCE_COMMIT}
- CLI entrypoint: ${CLI_PATH}
- Source present: ${SOURCE_PRESENT}
- Dependencies present: ${DEPENDENCIES_PRESENT}
- Ladybug extensions available: ${LADYBUG_EXTENSIONS_AVAILABLE}
- Ladybug extensions required: ${GITNEXUS_REQUIRE_LADYBUG_EXTENSIONS}
- Ladybug classification: ${LADYBUG_CLASSIFICATION}
- Index present: ${INDEX_PRESENT}
- Exit code: ${EXIT_CODE}
EOF

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "gitnexus",
  "target": "${GITNEXUS_TARGET}",
  "summary": {"total": 0, "critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0},
  "findings": []
}
JSON

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

emit-job-report \
    --tool gitnexus \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "mode=${GITNEXUS_MODE}" \
    --extra "gitnexus_version=${VERSION}" \
    --extra "source_repo=${GITNEXUS_SOURCE_REPO}" \
    --extra "source_ref=${GITNEXUS_SOURCE_REF}" \
    --extra "source_commit=${GITNEXUS_SOURCE_COMMIT}" \
    --extra "cli_entrypoint=${CLI_PATH}" \
    --extra "source_present=${SOURCE_PRESENT}" \
    --extra "dependencies_present=${DEPENDENCIES_PRESENT}" \
    --extra "ladybug_extensions_available=${LADYBUG_EXTENSIONS_AVAILABLE}" \
    --extra "ladybug_extensions_required=${GITNEXUS_REQUIRE_LADYBUG_EXTENSIONS}" \
    --extra "ladybug_classification=${LADYBUG_CLASSIFICATION}" \
    --extra "index_present=${INDEX_PRESENT}" \
    --extra "exit_code=${EXIT_CODE}"

exit "${EXIT_CODE}"
