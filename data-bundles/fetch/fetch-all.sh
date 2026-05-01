#!/usr/bin/env bash
# Fetch all configured connected-side datasets into data-bundles/sources.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_ROOT="${1:-data-bundles/sources}"

: "${SEMGREP_RULES_REPO_URL:=https://github.com/semgrep/semgrep-rules.git}"
: "${CODEQL_PACKS:=codeql/cpp-queries codeql/python-queries codeql/rust-queries}"
export SEMGREP_RULES_REPO_URL CODEQL_PACKS

FETCHERS=(
    fetch-cisa-kev.sh
    fetch-cwe.sh
    fetch-capec.sh
    fetch-mitre-attack.sh
    fetch-epss.sh
    fetch-nvd.sh
    fetch-osv-db.sh
    fetch-ladybug-extensions.sh
    fetch-yara-rules.sh
    fetch-semgrep-rules.sh
    fetch-codeql-packs.sh
    fetch-vendor-advisories.sh
    fetch-python-wheels.sh
    fetch-frontend-npm-cache.sh
)

mkdir -p "${OUT_ROOT}"
OUT_ROOT="$(cd "${OUT_ROOT}" && pwd)"   # docker run -v requires absolute paths
for fetcher in "${FETCHERS[@]}"; do
    "${SCRIPT_DIR}/${fetcher}" "${OUT_ROOT}"
done

if [[ "${INCLUDE_GITHUB_ADVISORY_DB:-0}" != "0" ]]; then
    "${SCRIPT_DIR}/fetch-github-advisory-db.sh" "${OUT_ROOT}"
else
    printf '==> Skipping GitHub Advisory DB (INCLUDE_GITHUB_ADVISORY_DB=0)\n'
fi

printf '==> Data fetch complete: %s\n' "${OUT_ROOT}"
