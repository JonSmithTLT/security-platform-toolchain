#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${1:-data-bundles/sources}"

fail() {
    printf 'data-bundle-smoke failed: %s\n' "$*" >&2
    exit 1
}

require_file() {
    local path="$1"
    [[ -f "${path}" ]] || fail "missing file: ${path}"
}

require_glob() {
    local pattern="$1"
    compgen -G "${pattern}" >/dev/null || fail "missing files matching: ${pattern}"
}

require_find() {
    local dir="$1"
    local name="$2"
    find "${dir}" -name "${name}" -type f | grep -q . || fail "missing ${name} under ${dir}"
}

require_file "${DATA_DIR}/cisa-kev/metadata.json"
require_file "${DATA_DIR}/cwe/metadata.json"
require_file "${DATA_DIR}/capec/metadata.json"
require_file "${DATA_DIR}/mitre-attack/metadata.json"
require_file "${DATA_DIR}/nvd/metadata.json"
require_file "${DATA_DIR}/github-advisory-db/metadata.json"
require_glob "${DATA_DIR}/osv/osv-scanner/*/all.zip"
require_glob "${DATA_DIR}/ladybug-extensions/*/*/fts/libfts.lbug_extension"
require_glob "${DATA_DIR}/ladybug-extensions/*/*/vector/libvector.lbug_extension"
require_find "${DATA_DIR}/yara-rules" "*.yar"
require_find "${DATA_DIR}/semgrep-rules" "*.yml"

printf 'Data bundle smoke passed: %s\n' "${DATA_DIR}"
