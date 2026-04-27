#!/usr/bin/env bash
# Robust cleanup for generated artifact paths that may contain container output.

set -euo pipefail

if [[ "$#" -eq 0 ]]; then
    printf 'Usage: scripts/clean-paths.sh PATH [PATH ...]\n' >&2
    exit 2
fi

failed=0
for path in "$@"; do
    [[ -e "${path}" ]] || continue
    printf '==> Removing %s\n' "${path}"
    chmod -R u+rwX "${path}" 2>/dev/null || true
    if rm -rf "${path}" 2>/dev/null; then
        continue
    fi

    # Some tools create mixed-mode trees; retry with a deeper chmod pass.
    find "${path}" -depth -exec chmod u+rwX {} + 2>/dev/null || true
    if rm -rf "${path}" 2>/dev/null; then
        continue
    fi

    printf 'ERROR: could not remove %s\n' "${path}" >&2
    printf '       Close processes using this path, then retry. If files are root-owned, run cleanup from the host/user that created them.\n' >&2
    if command -v wslpath >/dev/null 2>&1 && win_path="$(wslpath -w "${path}" 2>/dev/null)"; then
        printf '       On WSL/Windows mounts, clear stuck ACL/metadata entries from Windows PowerShell:\n' >&2
        printf "       Remove-Item -LiteralPath '%s' -Recurse -Force\n" "${win_path//\'/\'\'}" >&2
    fi
    failed=1
done

exit "${failed}"
