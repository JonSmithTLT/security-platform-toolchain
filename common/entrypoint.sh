#!/usr/bin/env bash
# common/entrypoint.sh
# Standard container entrypoint for every security-platform-toolchain image.
# Sources logging helpers, configures signal traps, then exec's the tool.
#
# Usage (in a Dockerfile):
#   COPY common/entrypoint.sh /usr/local/bin/entrypoint.sh
#   ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
#   CMD ["<tool-specific-command>"]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logging helpers (present in every image at a known path)
# shellcheck source=common/logging.sh
if [[ -f "${SCRIPT_DIR}/logging.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/logging.sh"
elif [[ -f "/usr/local/lib/spt/logging.sh" ]]; then
    # shellcheck disable=SC1091
    source "/usr/local/lib/spt/logging.sh"
else
    # Minimal fallback so the container still boots
    log_info()  { echo "[INFO]  $*"; }
    log_warn()  { echo "[WARN]  $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

# ── Environment defaults ───────────────────────────────────────────────────
: "${JOB_ID:=unknown}"
: "${ARTIFACTS_DIR:=/artifacts}"
: "${LOG_LEVEL:=info}"

# ── Artifact directory setup ───────────────────────────────────────────────
mkdir -p "${ARTIFACTS_DIR}"

log_info "=== security-platform-toolchain entrypoint ==="
log_info "JOB_ID        : ${JOB_ID}"
log_info "ARTIFACTS_DIR : ${ARTIFACTS_DIR}"
log_info "LOG_LEVEL     : ${LOG_LEVEL}"

# ── Signal handling ────────────────────────────────────────────────────────
_cleanup() {
    local sig="${1:-EXIT}"
    log_warn "Caught signal ${sig}; cleaning up..."
}

trap '_cleanup INT'  INT
trap '_cleanup TERM' TERM
trap '_cleanup EXIT' EXIT

# ── Exec the tool ─────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    log_warn "No command supplied; starting interactive shell."
    exec /bin/bash
else
    log_info "Executing: $*"
    exec "$@"
fi
