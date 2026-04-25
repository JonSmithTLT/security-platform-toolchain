#!/usr/bin/env bash
# images/ghidra-mcp/run-ghidra-mcp.sh
# Runs bethington GhidraMCP modes or emits smoke-test metadata.

set -euo pipefail
source /usr/local/lib/spt/logging.sh

: "${GHIDRA_HOME:=/opt/ghidra}"
: "${GHIDRA_MCP_HOME:=/opt/ghidra-mcp}"
: "${GHIDRA_MCP_MODE:=smoke}"
: "${GHIDRA_MCP_PORT:=8089}"
: "${GHIDRA_MCP_BIND_ADDRESS:=127.0.0.1}"
: "${JAVA_OPTS:=-Xmx4g -XX:+UseG1GC}"
: "${ARTIFACTS_DIR:=/artifacts}"

if [[ "${GHIDRA_MCP_MODE}" == "bridge" ]]; then
    cd "${GHIDRA_MCP_HOME}"
    exec python3 bridge_mcp_ghidra.py "$@"
fi

if [[ "${GHIDRA_MCP_MODE}" == "headless" ]]; then
    HEADLESS_JAR=$(find "${GHIDRA_MCP_HOME}" /opt/ghidra-mcp-artifacts "${HOME}/.config/ghidra" -name 'GhidraMCPHeadless*.jar' -type f 2>/dev/null | head -1 || true)
    if [[ -z "${HEADLESS_JAR}" ]]; then
        log_error "Could not find GhidraMCP headless jar"
        exit 1
    fi
    # shellcheck disable=SC2086
    exec java ${JAVA_OPTS} -jar "${HEADLESS_JAR}" --bind "${GHIDRA_MCP_BIND_ADDRESS}" --port "${GHIDRA_MCP_PORT}" "$@"
fi

RESULTS_DIR="${ARTIFACTS_DIR}/results/ghidra-mcp"
RAW_DIR="${RESULTS_DIR}/raw"
mkdir -p "${RAW_DIR}" "${ARTIFACTS_DIR}/logs"

START_TIME=$(date +%s)
STATUS=success

"${GHIDRA_HOME}/support/analyzeHeadless" 2>&1 | head -40 > "${RAW_DIR}/analyzeHeadless-help.txt" || true
python3 "${GHIDRA_MCP_HOME}/bridge_mcp_ghidra.py" --help > "${RAW_DIR}/bridge-help.txt" 2>&1 || true
python3 - <<'PY' > "${RAW_DIR}/python-mcp-sdk.txt" 2>&1 || true
import importlib.metadata as metadata
print(metadata.version("mcp"))
PY
find "${GHIDRA_MCP_HOME}" /opt/ghidra-mcp-artifacts "${HOME}/.config/ghidra" \
    \( -name 'GhidraMCP*.jar' -o -name 'GhidraMCP*.zip' \) \
    -type f 2>/dev/null | sort > "${RAW_DIR}/installed-artifacts.txt" || true

SOURCE_REVISION="unknown"
if [[ -f "${GHIDRA_MCP_HOME}/.spt-source-revision" ]]; then
    SOURCE_REVISION=$(cat "${GHIDRA_MCP_HOME}/.spt-source-revision")
fi

cat > "${RAW_DIR}/environment.json" <<JSON
{
  "ghidra_home": "${GHIDRA_HOME}",
  "ghidra_mcp_home": "${GHIDRA_MCP_HOME}",
  "mode": "${GHIDRA_MCP_MODE}",
  "mcp_server": "bethington/ghidra-mcp",
  "mcp_ref": "${GHIDRA_MCP_REF:-unknown}",
  "source_revision": "${SOURCE_REVISION}",
  "headless_port": "${GHIDRA_MCP_PORT}",
  "headless_bind_address": "${GHIDRA_MCP_BIND_ADDRESS}"
}
JSON

cat > "${RESULTS_DIR}/tool-result.json" <<JSON
{
  "schema_version": "1.0.0",
  "tool": "ghidra-mcp",
  "target": "${GHIDRA_HOME}",
  "summary": {"total": 0, "critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0},
  "findings": []
}
JSON

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

emit-job-report \
    --tool ghidra-mcp \
    --status "${STATUS}" \
    --results-file "${RESULTS_DIR}/tool-result.json" \
    --extra "duration_seconds=${DURATION}"
