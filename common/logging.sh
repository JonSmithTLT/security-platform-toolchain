#!/usr/bin/env bash
# common/logging.sh
# Structured log helpers for security-platform-toolchain images.
# Source this file; do not execute it directly.
#
#   source /usr/local/lib/spt/logging.sh
#
# Environment variables:
#   LOG_LEVEL  — minimum severity to emit (debug|info|warn|error). Default: info.
#   NO_COLOR   — set to any non-empty value to suppress ANSI color codes.

# ── Severity levels (numeric for comparison) ──────────────────────────────
declare -A _SPT_LEVELS=([debug]=0 [info]=1 [warn]=2 [error]=3)

_spt_level_value() {
    local lvl="${1,,}"   # to lower-case
    echo "${_SPT_LEVELS[$lvl]:-1}"
}

_spt_current_level() {
    _spt_level_value "${LOG_LEVEL:-info}"
}

# ── ANSI colour helpers ────────────────────────────────────────────────────
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 2 ]]; then
    _C_RESET='\033[0m'
    _C_GRAY='\033[0;90m'
    _C_CYAN='\033[0;36m'
    _C_YELLOW='\033[0;33m'
    _C_RED='\033[0;31m'
else
    _C_RESET=''
    _C_GRAY=''
    _C_CYAN=''
    _C_YELLOW=''
    _C_RED=''
fi

# ── Core emit function ─────────────────────────────────────────────────────
_spt_emit() {
    local level="$1"; shift
    local color="$1"; shift
    local message="$*"

    if (( $(_spt_level_value "$level") < $(_spt_current_level) )); then
        return 0
    fi

    local ts
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local label
    label="$(printf '%-5s' "${level^^}")"

    # Write to stderr so it does not pollute stdout tool output
    printf "${color}%s [%s] %s${_C_RESET}\n" \
        "${_C_GRAY}${ts}${_C_RESET}" \
        "${color}${label}" \
        "${message}" >&2
}

# ── Public API ─────────────────────────────────────────────────────────────
log_debug() { _spt_emit debug "${_C_GRAY}"   "$@"; }
log_info()  { _spt_emit info  "${_C_CYAN}"   "$@"; }
log_warn()  { _spt_emit warn  "${_C_YELLOW}" "$@"; }
log_error() { _spt_emit error "${_C_RED}"    "$@"; }

# Convenience: log and exit with error
log_fatal() {
    log_error "$@"
    exit 1
}
