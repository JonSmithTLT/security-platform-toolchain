#!/usr/bin/env bash
# Preflight checks for long SPT release/build runs.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

BUNDLE_DIR="${BUNDLE_DIR:-offline-bundles/out}"
DATA_BUNDLE_DIR="${DATA_BUNDLE_DIR:-data-bundles/out}"
DATA_DIR="${DATA_DIR:-data-bundles/sources}"
MIN_FREE_GB="${MIN_FREE_GB:-30}"
ALLOW_SLOW_WORKTREE="${ALLOW_SLOW_WORKTREE:-0}"
NATIVE_WORKTREE="${NATIVE_WORKTREE:-${HOME}/spt-build/security-platform-toolchain}"

FAILURES=0
WARNINGS=0

if [[ -t 1 ]]; then
    RED="$(printf '\033[31m')"
    GREEN="$(printf '\033[32m')"
    YELLOW="$(printf '\033[33m')"
    RESET="$(printf '\033[0m')"
else
    RED=""
    GREEN=""
    YELLOW=""
    RESET=""
fi

pass() {
    printf '%sOK%s   %s\n' "${GREEN}" "${RESET}" "$1"
}

warn() {
    WARNINGS=$((WARNINGS + 1))
    printf '%sWARN%s %s\n' "${YELLOW}" "${RESET}" "$1"
}

fail() {
    FAILURES=$((FAILURES + 1))
    printf '%sFAIL%s %s\n' "${RED}" "${RESET}" "$1"
}

have() {
    command -v "$1" >/dev/null 2>&1
}

check_command() {
    local cmd="$1"
    if have "${cmd}"; then
        pass "found ${cmd}"
    else
        fail "missing required command: ${cmd}"
    fi
}

check_optional_command() {
    local cmd="$1"
    local why="$2"
    if have "${cmd}"; then
        pass "found optional ${cmd}"
    else
        warn "missing optional ${cmd}: ${why}"
    fi
}

check_writable_dir() {
    local dir="$1"
    mkdir -p "${dir}"
    local probe="${dir}/.spt-doctor-write-test"
    if : > "${probe}" 2>/dev/null; then
        rm -f "${probe}"
        pass "writable directory: ${dir}"
    else
        fail "not writable: ${dir}"
    fi
}

check_free_space() {
    local dir="$1"
    mkdir -p "${dir}"

    if ! have df; then
        warn "cannot check free space for ${dir}: df not found"
        return
    fi

    local free_kb free_gb
    free_kb="$(df -Pk "${dir}" 2>/dev/null | awk 'NR == 2 {print $4}')"
    if [[ -z "${free_kb}" ]]; then
        warn "cannot read free space for ${dir}"
        return
    fi

    free_gb=$((free_kb / 1024 / 1024))
    if (( free_gb < MIN_FREE_GB )); then
        fail "${dir} has ${free_gb} GiB free; need at least ${MIN_FREE_GB} GiB for release work"
    else
        pass "${dir} has ${free_gb} GiB free"
    fi
}

check_slow_worktree() {
    local path
    path="$(pwd -P)"

    case "${path}" in
        /mnt/[a-zA-Z]/*|/run/desktop/mnt/host/*|/[a-zA-Z]/Users/*|*OneDrive*)
            if [[ "${ALLOW_SLOW_WORKTREE}" == "1" ]]; then
                warn "worktree appears to be on a slow/sync-heavy path (${path}); ALLOW_SLOW_WORKTREE=1 is set"
            else
                fail "worktree appears to be on a slow/sync-heavy path (${path}); move release work to native Linux storage or set ALLOW_SLOW_WORKTREE=1"
                printf '      Suggested setup: make native-worktree NATIVE_WORKTREE=%q\n' "${NATIVE_WORKTREE}"
                printf '      Then run: cd %q && make doctor\n' "${NATIVE_WORKTREE}"
            fi
            ;;
        *)
            pass "worktree path looks suitable: ${path}"
            ;;
    esac
}

check_docker() {
    if ! have docker; then
        fail "missing required command: docker"
        return
    fi

    pass "found docker"

    if docker info >/dev/null 2>&1; then
        pass "Docker daemon is reachable"
    else
        fail "Docker daemon is not reachable"
        return
    fi

    if docker buildx version >/dev/null 2>&1; then
        pass "Docker buildx is available"
    else
        warn "Docker buildx not available; BuildKit cache-mount builds may fail depending on Docker version"
    fi
}

check_git_state() {
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        pass "inside a Git worktree"
    else
        fail "not inside a Git worktree"
        return
    fi

    if [[ -n "$(git status --porcelain)" ]]; then
        warn "Git worktree has local changes; release evidence should record this"
    else
        pass "Git worktree is clean"
    fi
}

printf 'SPT preflight doctor\n'
printf 'ROOT_DIR=%s\n' "${ROOT_DIR}"
printf 'MIN_FREE_GB=%s\n\n' "${MIN_FREE_GB}"

check_command bash
check_command git
check_command make
check_command python3
check_command tar
check_command split
check_command sha256sum
check_command awk
check_command sed
check_command find
check_optional_command gh "needed only for GitHub release creation/upload"

check_docker
check_git_state
check_slow_worktree

check_writable_dir "${BUNDLE_DIR}"
check_writable_dir "${DATA_BUNDLE_DIR}"
check_writable_dir "artifacts"

if [[ -d "${DATA_DIR}" ]]; then
    pass "data directory exists: ${DATA_DIR}"
else
    warn "data directory does not exist yet: ${DATA_DIR}"
fi

check_free_space "."
check_free_space "${BUNDLE_DIR}"
check_free_space "${DATA_BUNDLE_DIR}"

printf '\nDoctor summary: %d failure(s), %d warning(s)\n' "${FAILURES}" "${WARNINGS}"

if (( FAILURES > 0 )); then
    exit 1
fi
