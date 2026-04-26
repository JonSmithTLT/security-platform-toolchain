#!/usr/bin/env bash
# images/ghidra-exporter/run-ghidra-exporter.sh
# Controlled Ghidra export workflows for local binaries or MCP-backed contexts.

set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${GHIDRA_HOME:=/opt/ghidra}"
: "${GHIDRA_EXPORT_MODE:=headless-basic}"
: "${GHIDRA_TARGET:=/workspace}"
: "${GHIDRA_PROJECT:=/tmp/ghidra-project}"
: "${GHIDRA_PROJECT_NAME:=spt-project}"
: "${GHIDRA_ANALYSIS_TIMEOUT:=120}"
: "${GHIDRA_POST_SCRIPT:=}"
: "${GHIDRA_MCP_HOST:=}"
: "${GHIDRA_MCP_PORT:=}"
: "${GHIDRA_MCP_START_CMD:=}"
: "${ARTIFACTS_DIR:=/artifacts}"

RESULTS_DIR="${ARTIFACTS_DIR}/results/ghidra-exporter"
RAW_DIR="${RESULTS_DIR}/raw"
NORM_DIR="${RESULTS_DIR}/normalized"
REPORT_DIR="${RESULTS_DIR}/reports"
mkdir -p "${RAW_DIR}" "${NORM_DIR}" "${REPORT_DIR}" "${ARTIFACTS_DIR}/logs" "${GHIDRA_PROJECT}"

START_TIME=$(date +%s)
STATUS=success
TARGET_FILE="${GHIDRA_TARGET}"
TARGET_MODE="local_binary"
PROJECT_STATE="fresh_headless_analysis"
MCP_PID=""

resolve_target() {
    TARGET_FILE="${GHIDRA_TARGET}"
    if [[ -d "${TARGET_FILE}" ]]; then
        TARGET_FILE="$(find "${TARGET_FILE}" -type f -perm -111 | head -1)"
    fi
    if [[ -z "${TARGET_FILE}" || ! -f "${TARGET_FILE}" ]]; then
        log_error "GHIDRA_TARGET did not resolve to a file: ${GHIDRA_TARGET}"
        return 1
    fi
}

run_headless_basic() {
    resolve_target || return 1
    "${GHIDRA_HOME}/support/analyzeHeadless" "${GHIDRA_PROJECT}" "${GHIDRA_PROJECT_NAME}" \
        -import "${TARGET_FILE}" \
        -analysisTimeoutPerFile "${GHIDRA_ANALYSIS_TIMEOUT}" \
        -deleteProject \
        2>&1 | tee "${RAW_DIR}/analyzeHeadless.log" | tee "${ARTIFACTS_DIR}/logs/ghidra-exporter.log"
}

run_direct_script() {
    resolve_target || return 1
    args=(
        "${GHIDRA_HOME}/support/analyzeHeadless" "${GHIDRA_PROJECT}" "${GHIDRA_PROJECT_NAME}"
        -import "${TARGET_FILE}"
        -analysisTimeoutPerFile "${GHIDRA_ANALYSIS_TIMEOUT}"
    )
    if [[ -n "${GHIDRA_POST_SCRIPT}" ]]; then
        args+=(-postScript "${GHIDRA_POST_SCRIPT}")
    fi
    args+=(-deleteProject)
    "${args[@]}" 2>&1 | tee "${RAW_DIR}/analyzeHeadless.log" | tee "${ARTIFACTS_DIR}/logs/ghidra-exporter.log"
}

start_local_mcp_if_configured() {
    if [[ -n "${GHIDRA_MCP_HOST}" && -n "${GHIDRA_MCP_PORT}" ]]; then
        TARGET_MODE="existing_mcp_server"
        PROJECT_STATE="possibly_analyst_enriched"
        return 0
    fi
    if [[ -z "${GHIDRA_MCP_START_CMD}" ]]; then
        log_error "GHIDRA_EXPORT_MODE=mcp-scripted requires GHIDRA_MCP_HOST/GHIDRA_MCP_PORT or GHIDRA_MCP_START_CMD"
        return 1
    fi
    TARGET_MODE="local_mcp_server"
    PROJECT_STATE="container_owned_mcp_context"
    bash -lc "${GHIDRA_MCP_START_CMD}" > "${ARTIFACTS_DIR}/logs/ghidra-mcp-local.log" 2>&1 &
    MCP_PID="$!"
    sleep 2
}

run_mcp_scripted() {
    start_local_mcp_if_configured || return 1
    if [[ -z "${GHIDRA_MCP_HOST}" ]]; then
        GHIDRA_MCP_HOST="127.0.0.1"
    fi
    if [[ -z "${GHIDRA_MCP_PORT}" ]]; then
        GHIDRA_MCP_PORT="8080"
    fi

    log_info "Connecting to Ghidra/MCP context at ${GHIDRA_MCP_HOST}:${GHIDRA_MCP_PORT}"
    if ! timeout 5 bash -lc "cat < /dev/null > /dev/tcp/${GHIDRA_MCP_HOST}/${GHIDRA_MCP_PORT}" 2>/dev/null; then
        log_error "Could not connect to Ghidra/MCP endpoint ${GHIDRA_MCP_HOST}:${GHIDRA_MCP_PORT}"
        return 1
    fi

    cat > "${RAW_DIR}/mcp-export.json" <<JSON
{
  "schema_version": "1.0.0",
  "endpoint": "${GHIDRA_MCP_HOST}:${GHIDRA_MCP_PORT}",
  "script": "fixed-mcp-extraction",
  "status": "connected",
  "note": "MCP scripted export hook is present; concrete extraction commands should be pinned to the selected GhidraMCP tool contract."
}
JSON
    cat "${RAW_DIR}/mcp-export.json" | tee "${ARTIFACTS_DIR}/logs/ghidra-exporter.log" >/dev/null
}

cleanup() {
    if [[ -n "${MCP_PID}" ]]; then
        kill "${MCP_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

case "${GHIDRA_EXPORT_MODE}" in
    headless-basic)
        TARGET_MODE="local_binary"
        PROJECT_STATE="fresh_headless_analysis"
        run_headless_basic || STATUS=failure
        ;;
    direct-script)
        TARGET_MODE="local_binary"
        PROJECT_STATE="fresh_headless_analysis"
        run_direct_script || STATUS=failure
        ;;
    mcp-scripted)
        run_mcp_scripted || STATUS=failure
        ;;
    *)
        log_error "Unknown GHIDRA_EXPORT_MODE=${GHIDRA_EXPORT_MODE}; expected headless-basic, direct-script, or mcp-scripted"
        STATUS=failure
        ;;
esac

TARGET_VALUE="${TARGET_FILE}"
if [[ "${TARGET_MODE}" == *"mcp"* ]]; then
    TARGET_VALUE="${GHIDRA_MCP_HOST:-unknown}:${GHIDRA_MCP_PORT:-unknown}"
fi

cat > "${NORM_DIR}/ghidra-export.json" <<JSON
{
  "schema_version": "1.0.0",
  "export_mode": "${GHIDRA_EXPORT_MODE}",
  "target_mode": "${TARGET_MODE}",
  "project_state": "${PROJECT_STATE}",
  "target": "${TARGET_VALUE}",
  "ghidra_project": "${GHIDRA_PROJECT}",
  "ghidra_project_name": "${GHIDRA_PROJECT_NAME}",
  "post_script": "${GHIDRA_POST_SCRIPT}",
  "mcp_host": "${GHIDRA_MCP_HOST}",
  "mcp_port": "${GHIDRA_MCP_PORT}"
}
JSON

cat > "${REPORT_DIR}/ghidra-export-summary.md" <<EOF
# Ghidra Export Summary

- Export mode: ${GHIDRA_EXPORT_MODE}
- Target mode: ${TARGET_MODE}
- Project state: ${PROJECT_STATE}
- Target: ${TARGET_VALUE}
EOF

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "ghidra-exporter",
  "target": "${TARGET_VALUE}",
  "summary": {"total": 0, "critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0},
  "findings": []
}
JSON

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool ghidra-exporter \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}" \
    --extra "export_mode=${GHIDRA_EXPORT_MODE}" \
    --extra "target_mode=${TARGET_MODE}" \
    --extra "project_state=${PROJECT_STATE}"
