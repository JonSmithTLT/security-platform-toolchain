#!/usr/bin/env bash
# Sync this repo into a native WSL/Linux worktree for faster release builds.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

NATIVE_WORKTREE="${NATIVE_WORKTREE:-${HOME}/spt-build/security-platform-toolchain}"
ALLOW_NATIVE_DELETE="${ALLOW_NATIVE_DELETE:-0}"
RESET_NATIVE_WORKTREE="${RESET_NATIVE_WORKTREE:-0}"

if [[ "${NATIVE_WORKTREE}" != "${HOME}"/* ]]; then
    printf 'ERROR: NATIVE_WORKTREE must live under $HOME for safety: %s\n' "${NATIVE_WORKTREE}" >&2
    exit 2
fi

mkdir -p "${NATIVE_WORKTREE}"

if [[ ! -d "${NATIVE_WORKTREE}/.git" ]] && find "${NATIVE_WORKTREE}" -mindepth 1 -maxdepth 1 | grep -q .; then
    if [[ "${RESET_NATIVE_WORKTREE}" != "1" ]]; then
        cat >&2 <<EOF
ERROR: ${NATIVE_WORKTREE} already contains files but is not a Git worktree.
Run once with RESET_NATIVE_WORKTREE=1 to recreate the native build copy:

  make native-worktree RESET_NATIVE_WORKTREE=1
EOF
        exit 2
    fi

    printf 'Resetting non-Git native worktree contents: %s\n' "${NATIVE_WORKTREE}"
    find "${NATIVE_WORKTREE}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

if [[ ! -d "${NATIVE_WORKTREE}/.git" ]] && git rev-parse --show-toplevel >/dev/null 2>&1; then
    printf 'Initializing native Git metadata in target.\n'
    (
        cd "${NATIVE_WORKTREE}"
        git init -q
        if ! git remote get-url source >/dev/null 2>&1; then
            git remote add source "${ROOT_DIR}"
        fi
        git fetch -q --depth 1 source HEAD
        git checkout -q --detach FETCH_HEAD
    )
fi

delete_args=()
if [[ "${ALLOW_NATIVE_DELETE}" == "1" ]]; then
    delete_args+=(--delete)
fi

exclude_args=(
    --exclude .git/
    --exclude artifacts/
    --exclude offline-bundles/out/
    --exclude data-bundles/out/
    --exclude data-bundles/sources/
    --exclude '*.tar'
    --exclude '*.tar.gz'
    --exclude '*.tar.zst'
    --exclude '*.sha256'
)

printf 'Syncing repo to native worktree:\n'
printf '  source: %s\n' "${ROOT_DIR}"
printf '  target: %s\n' "${NATIVE_WORKTREE}"

if command -v rsync >/dev/null 2>&1; then
    rsync -a "${delete_args[@]}" "${exclude_args[@]}" "${ROOT_DIR}/" "${NATIVE_WORKTREE}/"
else
    printf 'WARN: rsync not found; using tar fallback without delete support.\n' >&2
    tar \
        --exclude='./.git' \
        --exclude='./artifacts' \
        --exclude='./offline-bundles/out' \
        --exclude='./data-bundles/out' \
        --exclude='./data-bundles/sources' \
        --exclude='*.tar' \
        --exclude='*.tar.gz' \
        --exclude='*.tar.zst' \
        --exclude='*.sha256' \
        -cf - . | tar -xf - -C "${NATIVE_WORKTREE}"
fi

cat <<EOF

Native worktree ready.

Run release/build work from WSL:

  cd "${NATIVE_WORKTREE}"
  make doctor
  make release-smoke TAG=<tag>

To prune files removed from the source worktree during the next sync:

  make native-worktree ALLOW_NATIVE_DELETE=1
EOF
