#!/usr/bin/env bash
# Fetch all configured connected-side datasets into data-bundles/sources.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_ROOT="${1:-data-bundles/sources}"

FETCHERS=(
    fetch-cisa-kev.sh
    fetch-cwe.sh
    fetch-capec.sh
    fetch-mitre-attack.sh
    fetch-epss.sh
    fetch-nvd.sh
    fetch-github-advisory-db.sh
    fetch-osv-db.sh
    fetch-yara-rules.sh
    fetch-semgrep-rules.sh
    fetch-codeql-packs.sh
    fetch-vendor-advisories.sh
)

mkdir -p "${OUT_ROOT}"
for fetcher in "${FETCHERS[@]}"; do
    "${SCRIPT_DIR}/${fetcher}" "${OUT_ROOT}"
done

printf '==> Data fetch complete: %s\n' "${OUT_ROOT}"
